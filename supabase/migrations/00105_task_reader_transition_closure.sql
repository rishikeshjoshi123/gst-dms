-- Work plan step 3: close the first production Task slice. Tasks remain
-- private state; authenticated members receive only explicit, tenant-safe read
-- projections and operational members use the revisioned command below.
BEGIN;

CREATE TABLE public.task_transition_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  command text NOT NULL CHECK (command IN (
    'start', 'complete', 'reopen', 'cancel', 'set_assignee',
    'set_due_date', 'clear_due_date'
  )),
  from_status public.task_status NOT NULL,
  to_status public.task_status NOT NULL,
  from_assignee_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  to_assignee_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  from_due_date date,
  to_due_date date,
  from_due_timezone text,
  to_due_timezone text,
  revision bigint NOT NULL CHECK (revision >= 2),
  idempotency_key uuid NOT NULL UNIQUE,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_transition_history_task_revision_unique UNIQUE (task_id, revision)
);
CREATE INDEX task_transition_history_task_idx
  ON public.task_transition_history (org_id, task_id, revision DESC);

CREATE TABLE public.task_transition_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  result_revision bigint NOT NULL CHECK (result_revision >= 2),
  result_status public.task_status NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_transition_receipts_actor_org_idx
  ON public.task_transition_receipts (actor_user_id, org_id, created_at DESC);

-- A Task-origin note retains its content and collaboration lifecycle, but its
-- copied legacy action-item fields can no longer be used as current Task state.
-- Even privileged database maintenance must use an explicit repair migration,
-- rather than silently restoring a second live Task state source.
CREATE OR REPLACE FUNCTION public.case_notes_protect_task_origin_action_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF EXISTS (
       SELECT 1
       FROM public.tasks AS task
       WHERE task.org_id = OLD.org_id
         AND task.origin_kind = 'case_note'
         AND task.origin_note_id = OLD.id
     )
     AND (
       NEW.is_action_item IS DISTINCT FROM OLD.is_action_item
       OR NEW.action_item_resolved IS DISTINCT FROM OLD.action_item_resolved
       OR NEW.action_item_assignee IS DISTINCT FROM OLD.action_item_assignee
       OR NEW.action_item_due_date IS DISTINCT FROM OLD.action_item_due_date
     ) THEN
    RAISE EXCEPTION 'Task-origin note action fields are immutable; use transition_task'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS case_notes_protect_task_origin_action_fields ON public.case_notes;
CREATE TRIGGER case_notes_protect_task_origin_action_fields
  BEFORE UPDATE ON public.case_notes
  FOR EACH ROW EXECUTE FUNCTION public.case_notes_protect_task_origin_action_fields();

CREATE OR REPLACE FUNCTION public.get_my_tasks(
  p_statuses public.task_status[] DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  task_id uuid,
  client_id uuid,
  matter_id uuid,
  document_id uuid,
  title text,
  priority public.task_priority,
  status public.task_status,
  assignee_user_id uuid,
  due_date date,
  due_time time without time zone,
  due_timezone text,
  revision bigint,
  created_at timestamptz,
  updated_at timestamptz,
  origin_available boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_org uuid;
  v_current_membership_count integer;
  v_active_membership_count integer;
BEGIN
  IF v_actor IS NULL OR p_limit IS NULL OR p_offset IS NULL
     OR p_limit < 1 OR p_limit > 200 OR p_offset < 0 THEN
    RETURN;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active')
  INTO v_current_membership_count, v_active_membership_count
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended');
  IF v_current_membership_count <> 1 OR v_active_membership_count <> 1 THEN
    RETURN;
  END IF;
  SELECT membership.org_id INTO v_org
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor AND membership.state = 'active';

  RETURN QUERY
  SELECT task.id, task.client_id, task.matter_id, task.document_id,
    task.title, task.priority, task.status, task.assignee_user_id,
    task.due_date, task.due_time, task.due_timezone, task.revision,
    task.created_at, task.updated_at,
    EXISTS (
      SELECT 1 FROM public.case_notes AS note
      WHERE note.id = task.origin_note_id AND note.org_id = task.org_id
        AND note.matter_id = task.matter_id AND note.deleted_at IS NULL
    )
  FROM public.tasks AS task
  JOIN public.clients AS client
    ON client.id = task.client_id AND client.org_id = task.org_id
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter
    ON matter.id = task.matter_id AND matter.org_id = task.org_id
    AND matter.client_id = task.client_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document
    ON document.id = task.document_id AND document.org_id = task.org_id
    AND document.matter_id = task.matter_id
    AND document.record_state = 'active' AND document.deleted_at IS NULL
  WHERE task.org_id = v_org
    AND task.lifecycle_state = 'active'
    AND (task.document_id IS NULL OR document.id IS NOT NULL)
    AND (p_statuses IS NULL OR task.status = ANY(p_statuses))
  ORDER BY task.due_date NULLS LAST, task.priority DESC, task.created_at DESC, task.id
  LIMIT p_limit OFFSET p_offset;
END $$;

CREATE OR REPLACE FUNCTION public.get_task_detail(p_task_id uuid)
RETURNS TABLE(
  task_id uuid,
  client_id uuid,
  matter_id uuid,
  document_id uuid,
  title text,
  description text,
  creator_user_id uuid,
  assignee_user_id uuid,
  priority public.task_priority,
  status public.task_status,
  due_date date,
  due_time time without time zone,
  due_timezone text,
  revision bigint,
  status_changed_at timestamptz,
  completed_at timestamptz,
  completed_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  origin_note_id uuid,
  origin_available boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE v_actor uuid := auth.uid(); v_org uuid; v_current_membership_count integer; v_active_membership_count integer;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active') INTO v_current_membership_count, v_active_membership_count FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended');
  IF v_current_membership_count <> 1 OR v_active_membership_count <> 1 THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state = 'active';

  RETURN QUERY
  SELECT task.id, task.client_id, task.matter_id, task.document_id, task.title,
    task.description, task.creator_user_id, task.assignee_user_id, task.priority,
    task.status, task.due_date, task.due_time, task.due_timezone, task.revision,
    task.status_changed_at, task.completed_at, task.completed_by, task.created_at,
    task.updated_at,
    CASE WHEN note.id IS NULL THEN NULL::uuid ELSE note.id END,
    note.id IS NOT NULL
  FROM public.tasks AS task
  JOIN public.clients AS client ON client.id = task.client_id AND client.org_id = task.org_id
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter ON matter.id = task.matter_id AND matter.org_id = task.org_id
    AND matter.client_id = task.client_id AND matter.record_state = 'active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document ON document.id = task.document_id AND document.org_id = task.org_id
    AND document.matter_id = task.matter_id AND document.record_state = 'active' AND document.deleted_at IS NULL
  LEFT JOIN public.case_notes AS note ON note.id = task.origin_note_id AND note.org_id = task.org_id
    AND note.matter_id = task.matter_id AND note.deleted_at IS NULL
  WHERE task.id = p_task_id AND task.org_id = v_org
    AND task.lifecycle_state = 'active'
    AND (task.document_id IS NULL OR document.id IS NOT NULL);
END $$;

CREATE OR REPLACE FUNCTION public.get_note_task_summaries(p_note_ids uuid[] DEFAULT NULL)
RETURNS TABLE(
  note_id uuid,
  task_id uuid,
  status public.task_status,
  assignee_user_id uuid,
  due_date date,
  due_time time without time zone,
  due_timezone text,
  revision bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE v_actor uuid := auth.uid(); v_org uuid; v_current_membership_count integer; v_active_membership_count integer;
BEGIN
  IF v_actor IS NULL OR p_note_ids IS NULL
     OR cardinality(p_note_ids) = 0 OR cardinality(p_note_ids) > 500 THEN
    RETURN;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active') INTO v_current_membership_count, v_active_membership_count FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended');
  IF v_current_membership_count <> 1 OR v_active_membership_count <> 1 THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state = 'active';

  RETURN QUERY
  SELECT note.id, task.id, task.status, task.assignee_user_id, task.due_date,
    task.due_time, task.due_timezone, task.revision
  FROM public.case_notes AS note
  JOIN public.tasks AS task
    ON task.org_id = note.org_id AND task.origin_kind = 'case_note'
    AND task.origin_note_id = note.id
  JOIN public.clients AS client ON client.id = task.client_id AND client.org_id = task.org_id
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  JOIN public.matters AS matter ON matter.id = task.matter_id AND matter.org_id = task.org_id
    AND matter.client_id = task.client_id AND matter.record_state = 'active' AND matter.deleted_at IS NULL
  LEFT JOIN public.documents AS document ON document.id = task.document_id AND document.org_id = task.org_id
    AND document.matter_id = task.matter_id AND document.record_state = 'active' AND document.deleted_at IS NULL
  WHERE note.org_id = v_org AND note.id = ANY(p_note_ids)
    AND note.deleted_at IS NULL AND note.matter_id = task.matter_id
    AND task.lifecycle_state = 'active'
    AND (task.document_id IS NULL OR document.id IS NOT NULL);
END $$;

CREATE OR REPLACE FUNCTION public.get_task_transition_history(p_task_id uuid)
RETURNS TABLE(
  transition_id uuid,
  command text,
  actor_user_id uuid,
  from_status public.task_status,
  to_status public.task_status,
  from_assignee_user_id uuid,
  to_assignee_user_id uuid,
  from_due_date date,
  to_due_date date,
  from_due_timezone text,
  to_due_timezone text,
  revision bigint,
  occurred_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE v_actor uuid := auth.uid(); v_org uuid; v_current_membership_count integer; v_active_membership_count integer;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active') INTO v_current_membership_count, v_active_membership_count FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended');
  IF v_current_membership_count <> 1 OR v_active_membership_count <> 1 THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state = 'active';
  IF v_org IS NULL OR NOT EXISTS (SELECT 1 FROM public.get_task_detail(p_task_id)) THEN RETURN; END IF;
  RETURN QUERY
  SELECT history.id, history.command, history.actor_user_id, history.from_status,
    history.to_status, history.from_assignee_user_id, history.to_assignee_user_id,
    history.from_due_date, history.to_due_date, history.from_due_timezone,
    history.to_due_timezone, history.revision, history.occurred_at
  FROM public.task_transition_history AS history
  WHERE history.task_id = p_task_id AND history.org_id = v_org
  ORDER BY history.revision ASC;
END $$;

CREATE OR REPLACE FUNCTION public.transition_task(
  p_task_id uuid,
  p_command text,
  p_expected_revision bigint,
  p_idempotency_key uuid,
  p_assignee_user_id uuid DEFAULT NULL,
  p_due_date date DEFAULT NULL
)
RETURNS TABLE(code text, task_id uuid, revision bigint, status public.task_status, replayed boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid(); v_org uuid; v_membership_id uuid; v_role public.org_member_role; v_current_membership_count integer; v_active_membership_count integer;
  v_task public.tasks%ROWTYPE; v_previous public.tasks%ROWTYPE;
  v_receipt public.task_transition_receipts%ROWTYPE;
  v_timezone text; v_fingerprint text; v_command text := nullif(btrim(p_command), '');
  v_status public.task_status; v_assignee uuid; v_due_date date; v_due_timezone text;
  v_status_changed boolean := false;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL OR p_idempotency_key IS NULL
     OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR v_command IS NULL OR v_command NOT IN (
       'start', 'complete', 'reopen', 'cancel', 'set_assignee', 'set_due_date', 'clear_due_date'
     ) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;
  IF (v_command = 'set_assignee' AND p_assignee_user_id IS NULL)
     OR (v_command = 'set_due_date' AND p_due_date IS NULL)
     OR (v_command IN ('start', 'complete', 'reopen', 'cancel', 'clear_due_date')
         AND (p_assignee_user_id IS NOT NULL OR p_due_date IS NOT NULL)) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 100));
  -- Revalidate current membership before a receipt lookup. A replay cannot act
  -- as an access grant after suspension or removal.
  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active') INTO v_current_membership_count, v_active_membership_count FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended');
  IF v_current_membership_count <> 1 OR v_active_membership_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;
  SELECT membership.org_id, membership.id, membership.role INTO v_org, v_membership_id, v_role FROM public.organisation_memberships AS membership WHERE membership.user_id = v_actor AND membership.state = 'active';
  IF v_org IS NULL OR (v_role = 'viewer' AND NOT EXISTS (
    SELECT 1 FROM public.organisations AS organisation
    WHERE organisation.id = v_org AND organisation.owner_membership_id = v_membership_id
  )) THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'task_id', p_task_id, 'command', v_command, 'expected_revision', p_expected_revision,
    'assignee_user_id', p_assignee_user_id, 'due_date', p_due_date
  )::text, 'utf8'), 'sha256'), 'hex');
  SELECT * INTO v_receipt FROM public.task_transition_receipts
  WHERE idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_org
       OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    ELSE
      -- A successful receipt is never a lease on a Task that has since become
      -- suspended, trashed, deleted, or otherwise unavailable.
      IF NOT EXISTS (
        SELECT 1
        FROM public.tasks AS task
        JOIN public.clients AS client ON client.id = task.client_id AND client.org_id = task.org_id
          AND client.record_state = 'active' AND client.deleted_at IS NULL
        JOIN public.matters AS matter ON matter.id = task.matter_id AND matter.org_id = task.org_id
          AND matter.client_id = task.client_id AND matter.record_state = 'active' AND matter.deleted_at IS NULL
        LEFT JOIN public.documents AS document ON document.id = task.document_id AND document.org_id = task.org_id
          AND document.matter_id = task.matter_id AND document.record_state = 'active' AND document.deleted_at IS NULL
        WHERE task.id = v_receipt.task_id AND task.org_id = v_org
          AND task.lifecycle_state = 'active'
          AND (task.document_id IS NULL OR document.id IS NOT NULL)
      ) THEN
        RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
      END IF;
      RETURN QUERY SELECT 'ok'::text, v_receipt.task_id, v_receipt.result_revision,
        v_receipt.result_status, true;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_task
  FROM public.tasks AS task
  WHERE task.id = p_task_id AND task.org_id = v_org
  FOR UPDATE;
  IF v_task.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;
  IF v_task.lifecycle_state <> 'active'
     OR NOT EXISTS (
       SELECT 1 FROM public.clients AS client
       JOIN public.matters AS matter ON matter.id = v_task.matter_id AND matter.org_id = v_task.org_id
         AND matter.client_id = v_task.client_id AND matter.record_state = 'active' AND matter.deleted_at IS NULL
       WHERE client.id = v_task.client_id AND client.org_id = v_task.org_id
         AND client.record_state = 'active' AND client.deleted_at IS NULL
     )
     OR (v_task.document_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.documents AS document
       WHERE document.id = v_task.document_id AND document.org_id = v_task.org_id
         AND document.matter_id = v_task.matter_id
         AND document.record_state = 'active' AND document.deleted_at IS NULL
     )) THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::bigint, NULL::public.task_status, false;
    RETURN;
  END IF;
  IF v_task.revision <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict'::text, v_task.id, v_task.revision, v_task.status, false;
    RETURN;
  END IF;
  v_previous := v_task;

  v_status := v_task.status;
  v_assignee := v_task.assignee_user_id;
  v_due_date := v_task.due_date;
  v_due_timezone := v_task.due_timezone;
  IF v_command = 'start' THEN
    IF v_task.status <> 'open' THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_status := 'in_progress'; v_status_changed := true;
  ELSIF v_command = 'complete' THEN
    IF v_task.status NOT IN ('open', 'in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_status := 'completed'; v_status_changed := true;
  ELSIF v_command = 'reopen' THEN
    IF v_task.status NOT IN ('completed', 'cancelled') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_status := 'open'; v_status_changed := true;
  ELSIF v_command = 'cancel' THEN
    IF v_task.status NOT IN ('open', 'in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_status := 'cancelled'; v_status_changed := true;
  ELSIF v_command = 'set_assignee' THEN
    IF v_task.status NOT IN ('open', 'in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.organisation_memberships AS assignee
      LEFT JOIN public.organisations AS organisation ON organisation.id = assignee.org_id
      WHERE assignee.org_id = v_org AND assignee.user_id = p_assignee_user_id
        AND assignee.state = 'active'
        AND (assignee.role IN ('admin', 'associate') OR organisation.owner_membership_id = assignee.id)
    ) THEN RETURN QUERY SELECT 'invalid_assignee'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_assignee := p_assignee_user_id;
  ELSIF v_command = 'set_due_date' THEN
    IF v_task.status NOT IN ('open', 'in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    SELECT settings.timezone INTO v_timezone
    FROM public.organisation_operational_settings AS settings
    WHERE settings.org_id = v_org FOR KEY SHARE;
    IF v_timezone IS NULL OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN
      RETURN QUERY SELECT 'invalid_timezone'::text, v_task.id, v_task.revision, v_task.status, false; RETURN;
    END IF;
    v_due_date := p_due_date; v_due_timezone := v_timezone;
  ELSIF v_command = 'clear_due_date' THEN
    IF v_task.status NOT IN ('open', 'in_progress') THEN RETURN QUERY SELECT 'invalid_transition'::text, v_task.id, v_task.revision, v_task.status, false; RETURN; END IF;
    v_due_date := NULL; v_due_timezone := NULL;
  END IF;

  UPDATE public.tasks AS task
  SET status = v_status,
      assignee_user_id = v_assignee,
      due_date = v_due_date,
      due_time = CASE WHEN v_command IN ('set_due_date', 'clear_due_date') THEN NULL ELSE task.due_time END,
      due_timezone = v_due_timezone,
      revision = task.revision + 1,
      status_changed_at = CASE WHEN v_status_changed THEN now() ELSE task.status_changed_at END,
      status_changed_by = CASE WHEN v_status_changed THEN v_actor ELSE task.status_changed_by END,
      completed_at = CASE WHEN v_status = 'completed' THEN now() ELSE NULL END,
      completed_by = CASE WHEN v_status = 'completed' THEN v_actor ELSE NULL END,
      updated_at = now()
  WHERE task.id = v_task.id
  RETURNING * INTO v_task;

  INSERT INTO public.task_transition_history (
    org_id, task_id, actor_user_id, command, from_status, to_status,
    from_assignee_user_id, to_assignee_user_id, from_due_date, to_due_date,
    from_due_timezone, to_due_timezone, revision, idempotency_key
  ) VALUES (
    v_org, v_task.id, v_actor, v_command,
    v_previous.status, v_task.status,
    v_previous.assignee_user_id, v_task.assignee_user_id,
    v_previous.due_date, v_task.due_date,
    v_previous.due_timezone, v_task.due_timezone,
    v_task.revision, p_idempotency_key
  );

  INSERT INTO public.task_transition_receipts (
    org_id, actor_user_id, idempotency_key, request_fingerprint, task_id, result_revision, result_status
  ) VALUES (v_org, v_actor, p_idempotency_key, v_fingerprint, v_task.id, v_task.revision, v_task.status);
  RETURN QUERY SELECT 'ok'::text, v_task.id, v_task.revision, v_task.status, false;
END $$;

ALTER TABLE public.task_transition_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_transition_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_transition_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_transition_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.task_transition_history, public.task_transition_receipts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.case_notes_protect_task_origin_action_fields() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_tasks(public.task_status[], integer, integer), public.get_task_detail(uuid), public.get_note_task_summaries(uuid[]), public.get_task_transition_history(uuid), public.transition_task(uuid, text, bigint, uuid, uuid, date) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_tasks(public.task_status[], integer, integer), public.get_task_detail(uuid), public.get_note_task_summaries(uuid[]), public.get_task_transition_history(uuid), public.transition_task(uuid, text, bigint, uuid, uuid, date) TO authenticated;

COMMENT ON FUNCTION public.transition_task(uuid, text, bigint, uuid, uuid, date) IS
  'Authenticated Task command with active-membership, active-context, CAS revision, and idempotent-replay fences. It never mutates case_notes.';
COMMENT ON FUNCTION public.get_note_task_summaries(uuid[]) IS
  'Authenticated read-only Task summary for current active Notes origins; legacy note action fields are not current Task state.';
COMMIT;
