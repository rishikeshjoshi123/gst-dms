-- First-class Task foundation and the live note action-item compatibility
-- adapter.  There is intentionally no Task UI/read model in this migration.
BEGIN;

CREATE TYPE public.task_priority AS ENUM ('low', 'normal', 'high', 'urgent');
CREATE TYPE public.task_status AS ENUM ('open', 'in_progress', 'completed', 'cancelled', 'suspended');
CREATE TYPE public.task_lifecycle_state AS ENUM ('active', 'archived');

CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  client_id uuid,
  matter_id uuid,
  document_id uuid,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
  description text CHECK (description IS NULL OR char_length(description) <= 20000),
  origin_kind text NOT NULL CHECK (origin_kind = 'case_note'),
  origin_note_id uuid NOT NULL,
  origin_snapshot text NOT NULL CHECK (char_length(origin_snapshot) BETWEEN 1 AND 20000),
  creator_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  assignee_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  priority public.task_priority NOT NULL DEFAULT 'normal',
  status public.task_status NOT NULL DEFAULT 'open',
  due_date date,
  due_time time without time zone,
  due_timezone text,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  lifecycle_state public.task_lifecycle_state NOT NULL DEFAULT 'active',
  status_changed_at timestamptz NOT NULL DEFAULT now(),
  status_changed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  completed_at timestamptz,
  completed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tasks_context_shape CHECK (
    (matter_id IS NULL AND document_id IS NULL)
    OR matter_id IS NOT NULL
  ),
  CONSTRAINT tasks_due_contract CHECK (
    (due_date IS NULL AND due_time IS NULL AND due_timezone IS NULL)
    OR (due_date IS NOT NULL AND due_time IS NULL AND due_timezone IS NOT NULL)
    OR (due_date IS NOT NULL AND due_time IS NOT NULL AND due_timezone IS NOT NULL)
  ),
  CONSTRAINT tasks_completion_contract CHECK (
    (status = 'completed' AND completed_at IS NOT NULL AND completed_by IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL AND completed_by IS NULL)
  ),
  CONSTRAINT tasks_origin_one_note_once UNIQUE (org_id, origin_kind, origin_note_id)
);
CREATE INDEX tasks_org_assignee_active_idx
  ON public.tasks (org_id, assignee_user_id, due_date, id)
  WHERE lifecycle_state = 'active' AND status IN ('open', 'in_progress');
CREATE INDEX tasks_org_matter_active_idx
  ON public.tasks (org_id, matter_id, id)
  WHERE lifecycle_state = 'active';

-- Context/origin IDs deliberately remain stable locators rather than delete
-- cascades: soft-deleting or permanently purging a note must not delete or
-- rewrite its Task. Future Task read/Trash commands revalidate them.
COMMENT ON TABLE public.tasks IS
  'Private Task state. The initial live writer is create_note_with_optional_task; note edits/deletes and legacy completion toggles do not mutate Tasks.';
COMMENT ON COLUMN public.tasks.origin_note_id IS
  'Stable case_notes locator validated by the creating command; no FK so source purge cannot silently rewrite or delete the Task.';
COMMENT ON COLUMN public.tasks.due_time IS
  'Optional local wall-clock time. A null due_time with due_date remains date-only and is never interpreted as UTC midnight.';

CREATE TABLE public.task_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  note_id uuid NOT NULL,
  task_id uuid REFERENCES public.tasks(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX task_command_receipts_actor_org_idx
  ON public.task_command_receipts (actor_user_id, org_id, created_at DESC);

-- `createNote` is the sole production case-notes insert caller. Revoke direct
-- INSERT from both browser and service roles so neither normal nor action-item
-- note creation can bypass this atomic command. Existing note updates/deletes
-- retain their compatibility paths; they do not mutate Tasks.
REVOKE INSERT ON TABLE public.case_notes FROM PUBLIC, anon, authenticated, service_role;

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
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_org uuid;
  v_actor_role public.org_member_role;
  v_client uuid;
  v_note public.case_notes%ROWTYPE;
  v_task uuid;
  v_receipt public.task_command_receipts%ROWTYPE;
  v_parent public.case_notes%ROWTYPE;
  v_timezone text;
  v_fingerprint text;
  v_title text;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR p_matter_id IS NULL
     OR p_content IS NULL OR btrim(p_content) = '' OR char_length(p_content) > 20000
     OR p_template_type IS NULL OR p_is_action_item IS NULL
     OR (p_page_number IS NOT NULL AND p_page_number < 1)
     OR (p_quote IS NOT NULL AND char_length(p_quote) > 20000) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  -- The global key is serialised before lookup. Reuse by another actor,
  -- tenant, subject, or changed payload cannot disclose or replay a command.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 95));
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'matter_id', p_matter_id,
    'document_id', p_document_id,
    'content', p_content,
    'template_type', p_template_type::text,
    'is_action_item', p_is_action_item,
    'action_item_assignee', p_action_item_assignee,
    'action_item_due_date', p_action_item_due_date,
    'parent_note_id', p_parent_note_id,
    'quote', p_quote,
    'page_number', p_page_number
  )::text, 'utf8'), 'sha256'), 'hex');
  SELECT * INTO v_receipt FROM public.task_command_receipts
    WHERE idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::uuid, false;
    ELSE
      RETURN QUERY SELECT 'ok'::text, v_receipt.note_id, v_receipt.task_id, true;
    END IF;
    RETURN;
  END IF;

  SELECT membership.org_id, membership.role
    INTO v_org, v_actor_role
  FROM public.organisation_memberships membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  ORDER BY membership.created_at DESC
  LIMIT 1;
  IF v_org IS NULL OR v_actor_role = 'viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  SELECT matter.client_id INTO v_client
  FROM public.matters matter
  JOIN public.clients client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id AND matter.org_id = v_org
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR KEY SHARE OF matter, client;
  IF v_client IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  IF p_document_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.documents document
    WHERE document.id = p_document_id AND document.org_id = v_org
      AND document.matter_id = p_matter_id AND document.record_state = 'active'
      AND document.deleted_at IS NULL
    FOR KEY SHARE
  ) THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  IF p_parent_note_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM public.case_notes parent_note
    WHERE parent_note.id = p_parent_note_id AND parent_note.org_id = v_org
      AND parent_note.matter_id = p_matter_id AND parent_note.deleted_at IS NULL
    FOR KEY SHARE;
    IF v_parent.id IS NULL THEN
      RETURN QUERY SELECT 'invalid_parent_note'::text, NULL::uuid, NULL::uuid, false;
      RETURN;
    END IF;
  END IF;

  IF p_is_action_item AND p_action_item_assignee IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.organisation_memberships assignee
    WHERE assignee.org_id = v_org AND assignee.user_id = p_action_item_assignee
      AND assignee.state = 'active' AND assignee.role IN ('admin', 'associate')
  ) THEN
    RETURN QUERY SELECT 'invalid_assignee'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  -- Action fields on ordinary notes are rejected rather than retained as a
  -- second source of task truth.
  IF NOT p_is_action_item AND (p_action_item_assignee IS NOT NULL OR p_action_item_due_date IS NOT NULL) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, false;
    RETURN;
  END IF;

  IF p_is_action_item THEN
    SELECT profile.timezone INTO v_timezone
    FROM public.user_profiles profile WHERE profile.user_id = v_actor;
    v_timezone := COALESCE(v_timezone, 'Asia/Kolkata');
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone) THEN
      RETURN QUERY SELECT 'invalid_timezone'::text, NULL::uuid, NULL::uuid, false;
      RETURN;
    END IF;
  END IF;

  INSERT INTO public.case_notes (
    org_id, author_id, matter_id, document_id, content, template_type,
    is_action_item, action_item_assignee, action_item_due_date,
    parent_note_id, quote, page_number, is_pinned, action_item_resolved
  ) VALUES (
    v_org, v_actor, p_matter_id, p_document_id, p_content, p_template_type,
    p_is_action_item, CASE WHEN p_is_action_item THEN p_action_item_assignee ELSE NULL END,
    CASE WHEN p_is_action_item THEN p_action_item_due_date ELSE NULL END,
    p_parent_note_id, p_quote, p_page_number, false, false
  ) RETURNING * INTO v_note;

  IF p_is_action_item THEN
    v_title := left(regexp_replace(btrim(p_content), '[[:space:]]+', ' ', 'g'), 240);
    INSERT INTO public.tasks (
      org_id, client_id, matter_id, document_id, title, description,
      origin_kind, origin_note_id, origin_snapshot, creator_user_id,
      assignee_user_id, priority, status, due_date, due_time, due_timezone,
      revision, lifecycle_state, status_changed_by
    ) VALUES (
      v_org, v_client, p_matter_id, p_document_id, v_title, NULL,
      'case_note', v_note.id, p_content, v_actor, p_action_item_assignee,
      'normal', 'open', p_action_item_due_date, NULL,
      CASE WHEN p_action_item_due_date IS NULL THEN NULL ELSE v_timezone END,
      1, 'active', v_actor
    ) RETURNING id INTO v_task;
  END IF;

  INSERT INTO public.task_command_receipts (
    org_id, actor_user_id, idempotency_key, request_fingerprint, note_id, task_id
  ) VALUES (v_org, v_actor, p_idempotency_key, v_fingerprint, v_note.id, v_task);

  -- Activity 00094 intentionally has no valid Task subject type/definition.
  -- Do not forge a note/matter event here: a later approved Activity expansion
  -- must add the typed Task definition and append it in this same transaction.
  RETURN QUERY SELECT 'ok'::text, v_note.id, v_task, false;
END $$;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_command_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.tasks, public.task_command_receipts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_note_with_optional_task(
  uuid, text, public.note_template_type, boolean, uuid, uuid, uuid, date, uuid, text, integer
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_note_with_optional_task(
  uuid, text, public.note_template_type, boolean, uuid, uuid, uuid, date, uuid, text, integer
) TO authenticated;

COMMIT;
