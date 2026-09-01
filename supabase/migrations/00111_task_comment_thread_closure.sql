-- Work plan: the smallest live Task Comments consumer. Comment state is
-- private and can only be reached through the authenticated Task RPCs below.
BEGIN;

CREATE TABLE public.task_comment_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  next_sequence bigint NOT NULL DEFAULT 1 CHECK (next_sequence >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_comment_threads_one_per_task UNIQUE (task_id)
);

CREATE TABLE public.task_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  thread_id uuid NOT NULL REFERENCES public.task_comment_threads(id) ON DELETE RESTRICT,
  author_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 20000),
  sequence bigint NOT NULL CHECK (sequence >= 1),
  reply_to_comment_id uuid REFERENCES public.task_comments(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_comments_thread_sequence_unique UNIQUE (thread_id, sequence)
);
CREATE INDEX task_comments_thread_sequence_idx ON public.task_comments (thread_id, sequence);

CREATE TABLE public.task_comment_mentions (
  comment_id uuid NOT NULL REFERENCES public.task_comments(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  mentioned_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, mentioned_user_id)
);

CREATE TABLE public.task_comment_read_cursors (
  thread_id uuid NOT NULL REFERENCES public.task_comment_threads(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  observed_sequence bigint NOT NULL DEFAULT 0 CHECK (observed_sequence >= 0),
  observed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE public.task_comment_followers (
  thread_id uuid NOT NULL REFERENCES public.task_comment_threads(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  follow_source text NOT NULL CHECK (follow_source IN ('creator', 'assignee', 'explicit')),
  muted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (thread_id, user_id, follow_source)
);

-- A command key is unique before tenant/actor/payload checks. It is deliberately
-- independent of the visible comment, so a replay cannot become a capability
-- after membership or resource lifecycle changes.
CREATE TABLE public.task_comment_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE RESTRICT,
  comment_id uuid NOT NULL REFERENCES public.task_comments(id) ON DELETE RESTRICT,
  sequence bigint NOT NULL CHECK (sequence >= 1),
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.activity_event_definitions(
  event_type, event_version, category, subject_types, default_visibility, metadata_contract, renderer_key
) VALUES (
  'task.comment_posted', 1, 'work', ARRAY['task'], 'matter',
  '{"sequence":"integer","mention_count":"integer"}', 'task.comment_posted'
);

-- The RPCs derive all lineage, but keep the same invariant at the table
-- boundary so a future privileged maintenance path cannot manufacture a
-- cross-tenant thread, reply, cursor, mention, follower, or receipt.
CREATE OR REPLACE FUNCTION public.enforce_task_comment_lineage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'task_comment_threads' THEN
    IF NOT EXISTS (SELECT 1 FROM public.tasks AS task WHERE task.id = NEW.task_id AND task.org_id = NEW.org_id) THEN RAISE EXCEPTION 'Task comment thread lineage mismatch' USING ERRCODE = '23503'; END IF;
  ELSIF TG_TABLE_NAME = 'task_comments' THEN
    IF NOT EXISTS (SELECT 1 FROM public.task_comment_threads AS thread WHERE thread.id = NEW.thread_id AND thread.task_id = NEW.task_id AND thread.org_id = NEW.org_id)
      OR (NEW.reply_to_comment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.task_comments AS reply WHERE reply.id = NEW.reply_to_comment_id AND reply.thread_id = NEW.thread_id AND reply.org_id = NEW.org_id)) THEN RAISE EXCEPTION 'Task comment lineage mismatch' USING ERRCODE = '23503'; END IF;
  ELSIF TG_TABLE_NAME = 'task_comment_mentions' THEN
    IF NOT EXISTS (SELECT 1 FROM public.task_comments AS comment WHERE comment.id = NEW.comment_id AND comment.org_id = NEW.org_id) THEN RAISE EXCEPTION 'Task comment mention lineage mismatch' USING ERRCODE = '23503'; END IF;
  ELSIF TG_TABLE_NAME IN ('task_comment_read_cursors', 'task_comment_followers') THEN
    IF NOT EXISTS (SELECT 1 FROM public.task_comment_threads AS thread WHERE thread.id = NEW.thread_id AND thread.org_id = NEW.org_id) THEN RAISE EXCEPTION 'Task comment member-state lineage mismatch' USING ERRCODE = '23503'; END IF;
  ELSIF TG_TABLE_NAME = 'task_comment_command_receipts' THEN
    IF NOT EXISTS (SELECT 1 FROM public.task_comments AS comment WHERE comment.id = NEW.comment_id AND comment.task_id = NEW.task_id AND comment.org_id = NEW.org_id AND comment.sequence = NEW.sequence) THEN RAISE EXCEPTION 'Task comment receipt lineage mismatch' USING ERRCODE = '23503'; END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER task_comment_threads_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comment_threads FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();
CREATE TRIGGER task_comments_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comments FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();
CREATE TRIGGER task_comment_mentions_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comment_mentions FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();
CREATE TRIGGER task_comment_read_cursors_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comment_read_cursors FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();
CREATE TRIGGER task_comment_followers_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comment_followers FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();
CREATE TRIGGER task_comment_command_receipts_enforce_lineage BEFORE INSERT OR UPDATE ON public.task_comment_command_receipts FOR EACH ROW EXECUTE FUNCTION public.enforce_task_comment_lineage();

CREATE OR REPLACE FUNCTION public.task_comment_context_is_available(p_task_id uuid, p_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tasks AS task
    JOIN public.clients AS client ON client.id = task.client_id AND client.org_id = task.org_id
      AND client.record_state = 'active' AND client.deleted_at IS NULL
    JOIN public.matters AS matter ON matter.id = task.matter_id AND matter.org_id = task.org_id
      AND matter.client_id = task.client_id AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    LEFT JOIN public.documents AS document ON document.id = task.document_id AND document.org_id = task.org_id
      AND document.matter_id = task.matter_id AND document.record_state = 'active' AND document.deleted_at IS NULL
    WHERE task.id = p_task_id AND task.org_id = p_org_id AND task.lifecycle_state = 'active'
      AND task.status <> 'suspended'
      AND (task.document_id IS NULL OR document.id IS NOT NULL)
  );
$$;

CREATE OR REPLACE FUNCTION public.get_task_comment_thread(p_task_id uuid)
RETURNS TABLE(thread_id uuid, latest_sequence bigint, observed_sequence bigint, unread_count bigint)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_actor uuid := auth.uid(); v_org uuid;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS membership;
  IF v_org IS NULL OR NOT public.task_comment_context_is_available(p_task_id, v_org) THEN RETURN; END IF;
  RETURN QUERY
  SELECT thread.id, thread.next_sequence - 1, COALESCE(cursor.observed_sequence, 0),
    GREATEST(thread.next_sequence - 1 - COALESCE(cursor.observed_sequence, 0), 0)
  FROM public.task_comment_threads AS thread
  LEFT JOIN public.task_comment_read_cursors AS cursor
    ON cursor.thread_id = thread.id AND cursor.org_id = v_org AND cursor.user_id = v_actor
  WHERE thread.task_id = p_task_id AND thread.org_id = v_org;
END $$;

CREATE OR REPLACE FUNCTION public.get_task_comments(p_task_id uuid, p_after_sequence bigint DEFAULT 0, p_limit integer DEFAULT 200)
RETURNS TABLE(comment_id uuid, thread_id uuid, sequence bigint, author_user_id uuid, body text, reply_to_comment_id uuid, reply_to_sequence bigint, created_at timestamptz, mentioned_user_ids uuid[])
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
DECLARE v_actor uuid := auth.uid(); v_org uuid;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL OR p_after_sequence IS NULL OR p_after_sequence < 0 OR p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS membership;
  IF v_org IS NULL OR NOT public.task_comment_context_is_available(p_task_id, v_org) THEN RETURN; END IF;
  RETURN QUERY
  SELECT comment.id, comment.thread_id, comment.sequence, comment.author_user_id, comment.body,
    comment.reply_to_comment_id, reply.sequence, comment.created_at,
    COALESCE((SELECT array_agg(mention.mentioned_user_id ORDER BY mention.mentioned_user_id)
      FROM public.task_comment_mentions AS mention WHERE mention.comment_id = comment.id), ARRAY[]::uuid[])
  FROM public.task_comments AS comment
  JOIN public.task_comment_threads AS thread ON thread.id = comment.thread_id AND thread.org_id = v_org
  LEFT JOIN public.task_comments AS reply ON reply.id = comment.reply_to_comment_id AND reply.thread_id = comment.thread_id
  WHERE thread.task_id = p_task_id AND comment.org_id = v_org AND comment.sequence > p_after_sequence
  ORDER BY comment.sequence ASC LIMIT p_limit;
END $$;

CREATE OR REPLACE FUNCTION public.post_task_comment(
  p_task_id uuid, p_body text, p_idempotency_key uuid,
  p_reply_to_comment_id uuid DEFAULT NULL, p_mentioned_user_ids uuid[] DEFAULT NULL
)
RETURNS TABLE(code text, thread_id uuid, comment_id uuid, sequence bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid(); v_org uuid; v_membership_id uuid; v_role public.org_member_role;
  v_current_count integer := 0; v_active_count integer := 0; v_membership public.organisation_memberships%ROWTYPE;
  v_task public.tasks%ROWTYPE; v_thread public.task_comment_threads%ROWTYPE; v_receipt public.task_comment_command_receipts%ROWTYPE;
  v_mentions uuid[]; v_fingerprint text; v_sequence bigint; v_comment_id uuid; v_replay_thread_id uuid; v_activity_idempotency_key text;
BEGIN
  IF v_actor IS NULL OR p_task_id IS NULL OR p_idempotency_key IS NULL OR p_body IS NULL
     OR btrim(p_body) = '' OR char_length(p_body) > 20000
     OR (p_mentioned_user_ids IS NOT NULL AND cardinality(p_mentioned_user_ids) > 50) THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT mentioned_user_id ORDER BY mentioned_user_id), ARRAY[]::uuid[])
  INTO v_mentions FROM unnest(COALESCE(p_mentioned_user_ids, ARRAY[]::uuid[])) AS mention(mentioned_user_id)
  WHERE mentioned_user_id IS NOT NULL;
  IF cardinality(v_mentions) <> COALESCE(cardinality(p_mentioned_user_ids), 0) THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 111));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended') FOR UPDATE LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN
      v_active_count := v_active_count + 1; v_org := v_membership.org_id; v_membership_id := v_membership.id; v_role := v_membership.role;
    END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 OR (v_role = 'viewer' AND NOT EXISTS (
    SELECT 1 FROM public.organisations AS organisation WHERE organisation.id = v_org AND organisation.owner_membership_id = v_membership_id
  )) THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  -- Match the hierarchy Trash command's organisation lock before revalidating
  -- Task context. A matter/client/document cannot enter Trash between an
  -- apparently active check and the comment/Activity/outbox commit.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_org::text), pg_catalog.hashtext('hierarchical-resource-trash')
  );
  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'task_id',p_task_id,'body',p_body,'reply_to_comment_id',p_reply_to_comment_id,'mentioned_user_ids',v_mentions
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.task_comment_command_receipts WHERE idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_org OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSIF NOT public.task_comment_context_is_available(v_receipt.task_id, v_org) THEN
      RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSE
      SELECT comment.thread_id INTO v_replay_thread_id FROM public.task_comments AS comment WHERE comment.id = v_receipt.comment_id AND comment.org_id = v_org;
      RETURN QUERY SELECT 'ok'::text,v_replay_thread_id,v_receipt.comment_id,v_receipt.sequence,true;
    END IF;
    RETURN;
  END IF;
  SELECT * INTO v_task FROM public.tasks AS task WHERE task.id = p_task_id AND task.org_id = v_org FOR KEY SHARE;
  IF v_task.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF NOT public.task_comment_context_is_available(v_task.id, v_org) THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF p_reply_to_comment_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.task_comments AS reply JOIN public.task_comment_threads AS thread ON thread.id = reply.thread_id
    WHERE reply.id = p_reply_to_comment_id AND reply.org_id = v_org AND thread.task_id = v_task.id AND thread.org_id = v_org
  ) THEN RETURN QUERY SELECT 'invalid_reply'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_mentions) AS requested(user_id)
    LEFT JOIN public.organisation_memberships AS member ON member.org_id = v_org AND member.user_id = requested.user_id AND member.state = 'active'
    WHERE member.id IS NULL) THEN RETURN QUERY SELECT 'invalid_mentions'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  INSERT INTO public.task_comment_threads(org_id, task_id) VALUES (v_org, v_task.id)
  ON CONFLICT (task_id) DO UPDATE SET updated_at = EXCLUDED.updated_at
  RETURNING * INTO v_thread;
  UPDATE public.task_comment_threads SET next_sequence = next_sequence + 1, updated_at = now()
    WHERE id = v_thread.id RETURNING next_sequence - 1 INTO v_sequence;
  INSERT INTO public.task_comments(org_id, task_id, thread_id, author_user_id, body, sequence, reply_to_comment_id)
    VALUES (v_org, v_task.id, v_thread.id, v_actor, p_body, v_sequence, p_reply_to_comment_id) RETURNING id INTO v_comment_id;
  INSERT INTO public.task_comment_mentions(comment_id, org_id, mentioned_user_id, created_by_user_id)
    SELECT v_comment_id, v_org, requested.user_id, v_actor FROM unnest(v_mentions) AS requested(user_id);
  INSERT INTO public.task_comment_followers(thread_id, org_id, user_id, follow_source)
    SELECT v_thread.id, v_org, v_task.creator_user_id, 'creator'
    WHERE EXISTS (SELECT 1 FROM public.organisation_memberships AS member WHERE member.org_id=v_org AND member.user_id=v_task.creator_user_id AND member.state='active')
    ON CONFLICT DO NOTHING;
  INSERT INTO public.task_comment_followers(thread_id, org_id, user_id, follow_source)
    SELECT v_thread.id, v_org, v_task.assignee_user_id, 'assignee'
    WHERE v_task.assignee_user_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.organisation_memberships AS member WHERE member.org_id=v_org AND member.user_id=v_task.assignee_user_id AND member.state='active')
    ON CONFLICT DO NOTHING;
  INSERT INTO public.task_comment_command_receipts(org_id, actor_user_id, idempotency_key, request_fingerprint, task_id, comment_id, sequence)
    VALUES(v_org,v_actor,p_idempotency_key,v_fingerprint,v_task.id,v_comment_id,v_sequence);
  v_activity_idempotency_key := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','task.comment_posted','task_id',v_task.id,'comment_id',v_comment_id,
    'command_idempotency_key',p_idempotency_key,'org_id',v_org,'actor_id',v_actor
  )::text,'utf8'),'sha256'),'hex');
  PERFORM public.append_activity_event(
    v_org,'task.comment_posted',1::smallint,'user',v_actor,NULL,
    'task',v_task.id,v_task.client_id,v_task.matter_id,'Task','Task comment posted',
    jsonb_build_object('sequence',v_sequence,'mention_count',cardinality(v_mentions)),
    'task',v_task.id,NULL,NULL,NULL,v_activity_idempotency_key,now()
  );
  RETURN QUERY SELECT 'ok'::text,v_thread.id,v_comment_id,v_sequence,false;
END $$;

ALTER TABLE public.task_comment_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_threads FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_mentions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_mentions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_read_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_read_cursors FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_followers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_followers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_comment_command_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.task_comment_threads, public.task_comments, public.task_comment_mentions,
  public.task_comment_read_cursors, public.task_comment_followers, public.task_comment_command_receipts
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.task_comment_context_is_available(uuid,uuid), public.get_task_comment_thread(uuid),
  public.get_task_comments(uuid,bigint,integer), public.post_task_comment(uuid,text,uuid,uuid,uuid[]), public.enforce_task_comment_lineage()
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_task_comment_thread(uuid), public.get_task_comments(uuid,bigint,integer),
  public.post_task_comment(uuid,text,uuid,uuid,uuid[]) TO authenticated;

COMMENT ON FUNCTION public.post_task_comment(uuid,text,uuid,uuid,uuid[]) IS
  'Authenticated Task-only comment command. It locks exact-current membership, revalidates active resource context on replay, serialises a per-thread sequence, and never mutates Task or Notes state.';
COMMENT ON TABLE public.task_comment_threads IS 'Private one-to-one Task conversation identity. It is never a Notes thread.';
COMMIT;
