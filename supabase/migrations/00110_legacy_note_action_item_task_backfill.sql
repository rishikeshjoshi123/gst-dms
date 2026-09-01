-- Work plan step 3: migrate historic note action items without reviving the
-- legacy note fields as Task state. This is deliberately service-only: tenant
-- authority comes from the supplied scoped migration invocation, never from a
-- browser organisation choice or the newest membership.
BEGIN;

-- A note UUID is globally unique, so the original per-organisation uniqueness
-- fence was weaker than the one canonical Task per note contract. Keep the
-- existing constraint for reader locality and add this immutable source fence.
CREATE UNIQUE INDEX tasks_case_note_origin_global_unique
  ON public.tasks (origin_note_id)
  WHERE origin_kind = 'case_note';

CREATE TABLE public.task_legacy_note_backfill_diagnostics (
  source_note_id uuid PRIMARY KEY,
  source_org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  disposition text NOT NULL CHECK (disposition IN (
    'migrated',
    'existing_task',
    'existing_task_lineage_conflict',
    'deleted_note',
    'matter_context_unavailable',
    'document_context_unavailable',
    'invalid_assignee',
    'invalid_timezone',
    'invalid_origin_snapshot'
  )),
  task_id uuid REFERENCES public.tasks(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_legacy_note_backfill_diagnostics_task_shape CHECK (
    (disposition IN ('migrated', 'existing_task') AND task_id IS NOT NULL)
    OR (disposition NOT IN ('migrated', 'existing_task') AND task_id IS NULL)
  )
);
CREATE INDEX task_legacy_note_backfill_diagnostics_org_disposition_idx
  ON public.task_legacy_note_backfill_diagnostics (source_org_id, disposition, source_note_id);

-- A narrow aggregate report lets the trusted migration operator establish the
-- cut-over count without returning note content, titles, or arbitrary IDs.
CREATE VIEW public.task_legacy_note_backfill_reports AS
SELECT
  note.org_id,
  count(*) FILTER (WHERE note.is_action_item)::bigint AS source_count,
  count(diagnostic.source_note_id)::bigint AS disposed_count,
  count(*) FILTER (
    WHERE note.is_action_item AND diagnostic.source_note_id IS NULL
  )::bigint AS pending_count,
  count(*) FILTER (
    WHERE diagnostic.disposition = 'migrated'
  )::bigint AS migrated_count,
  count(*) FILTER (
    WHERE diagnostic.disposition = 'existing_task'
  )::bigint AS existing_task_count,
  count(*) FILTER (
    WHERE diagnostic.disposition NOT IN ('migrated', 'existing_task')
  )::bigint AS excluded_count
FROM public.case_notes AS note
LEFT JOIN public.task_legacy_note_backfill_diagnostics AS diagnostic
  ON diagnostic.source_note_id = note.id
GROUP BY note.org_id;

CREATE OR REPLACE FUNCTION public.backfill_legacy_note_action_items(
  p_org_id uuid,
  p_limit integer DEFAULT 250
)
RETURNS TABLE(disposition text, result_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_note public.case_notes%ROWTYPE;
  v_existing_task public.tasks%ROWTYPE;
  v_client_id uuid;
  v_timezone text;
  v_task_id uuid;
  v_disposition text;
  v_activity_idempotency_key text;
  v_title text;
BEGIN
  IF p_org_id IS NULL OR p_limit IS NULL OR p_limit < 1 OR p_limit > 500
     OR NOT EXISTS (SELECT 1 FROM public.organisations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'invalid legacy note Task backfill scope';
  END IF;

  -- Lock source rows before looking at the existing-origin fence. Overlapping
  -- service runs therefore divide work, while the global Task origin index is
  -- the final invariant if another trusted writer already owns the source.
  FOR v_note IN
    SELECT note.*
    FROM public.case_notes AS note
    LEFT JOIN public.task_legacy_note_backfill_diagnostics AS diagnostic
      ON diagnostic.source_note_id = note.id
    WHERE note.org_id = p_org_id
      AND note.is_action_item
      AND diagnostic.source_note_id IS NULL
    ORDER BY note.created_at, note.id
    LIMIT p_limit
    FOR UPDATE OF note SKIP LOCKED
  LOOP
    v_existing_task := NULL;
    v_client_id := NULL;
    v_timezone := NULL;
    v_task_id := NULL;
    v_disposition := NULL;

    -- Read the source's stable client lineage before classifying a pre-existing
    -- origin. Active/Trash eligibility is checked below only when a Task must
    -- be created; an existing Task is never silently repaired or rewritten.
    SELECT matter.client_id INTO v_client_id
    FROM public.matters AS matter
    WHERE matter.id = v_note.matter_id
      AND matter.org_id = v_note.org_id;

    SELECT * INTO v_existing_task
    FROM public.tasks AS task
    WHERE task.origin_kind = 'case_note'
      AND task.origin_note_id = v_note.id;

    IF v_existing_task.id IS NOT NULL THEN
      IF v_existing_task.org_id = v_note.org_id
         AND v_existing_task.client_id = v_client_id
         AND v_existing_task.matter_id = v_note.matter_id
         AND v_existing_task.document_id IS NOT DISTINCT FROM v_note.document_id THEN
        v_disposition := 'existing_task';
        v_task_id := v_existing_task.id;
      ELSE
        -- An existing origin is never repaired or overwritten by this
        -- migration. The explicit diagnostic is the safe hand-off for a
        -- privileged lineage repair contract.
        v_disposition := 'existing_task_lineage_conflict';
      END IF;
    ELSIF v_note.deleted_at IS NOT NULL THEN
      v_disposition := 'deleted_note';
    ELSIF btrim(v_note.content) = '' OR char_length(v_note.content) > 20000 THEN
      v_disposition := 'invalid_origin_snapshot';
    ELSE
      SELECT matter.client_id INTO v_client_id
      FROM public.matters AS matter
      JOIN public.clients AS client
        ON client.id = matter.client_id
        AND client.org_id = matter.org_id
      WHERE matter.id = v_note.matter_id
        AND matter.org_id = v_note.org_id
        AND matter.record_state = 'active'
        AND matter.deleted_at IS NULL
        AND client.record_state = 'active'
        AND client.deleted_at IS NULL
      FOR KEY SHARE OF matter, client;

      IF v_client_id IS NULL THEN
        v_disposition := 'matter_context_unavailable';
      ELSIF v_note.document_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.documents AS document
        WHERE document.id = v_note.document_id
          AND document.org_id = v_note.org_id
          AND document.matter_id = v_note.matter_id
          AND document.record_state = 'active'
          AND document.deleted_at IS NULL
        FOR KEY SHARE
      ) THEN
        v_disposition := 'document_context_unavailable';
      ELSIF v_note.action_item_assignee IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.organisation_memberships AS assignee
        LEFT JOIN public.organisations AS organisation
          ON organisation.id = assignee.org_id
        WHERE assignee.org_id = v_note.org_id
          AND assignee.user_id = v_note.action_item_assignee
          AND assignee.state = 'active'
          AND (assignee.role IN ('admin', 'associate')
               OR organisation.owner_membership_id = assignee.id)
      ) THEN
        v_disposition := 'invalid_assignee';
      ELSE
        SELECT settings.timezone INTO v_timezone
        FROM public.organisation_operational_settings AS settings
        WHERE settings.org_id = v_note.org_id
        FOR KEY SHARE;

        IF v_timezone IS NULL OR NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = v_timezone
        ) THEN
          v_disposition := 'invalid_timezone';
        ELSE
          v_title := left(regexp_replace(btrim(v_note.content), '[[:space:]]+', ' ', 'g'), 240);
          INSERT INTO public.tasks (
            org_id, client_id, matter_id, document_id, title, description,
            origin_kind, origin_note_id, origin_snapshot, creator_user_id,
            assignee_user_id, priority, status, due_date, due_time, due_timezone,
            revision, lifecycle_state, status_changed_at, status_changed_by,
            completed_at, completed_by, created_at, updated_at
          ) VALUES (
            v_note.org_id, v_client_id, v_note.matter_id, v_note.document_id,
            v_title, NULL, 'case_note', v_note.id, v_note.content, v_note.author_id,
            v_note.action_item_assignee, 'normal',
            CASE WHEN v_note.action_item_resolved THEN 'completed'::public.task_status ELSE 'open'::public.task_status END,
            v_note.action_item_due_date, NULL,
            CASE WHEN v_note.action_item_due_date IS NULL THEN NULL ELSE v_timezone END,
            1, 'active',
            CASE WHEN v_note.action_item_resolved THEN v_note.updated_at ELSE v_note.created_at END,
            v_note.author_id,
            CASE WHEN v_note.action_item_resolved THEN v_note.updated_at ELSE NULL END,
            CASE WHEN v_note.action_item_resolved THEN v_note.author_id ELSE NULL END,
            v_note.created_at, v_note.updated_at
          )
          ON CONFLICT (origin_note_id) WHERE origin_kind = 'case_note' DO NOTHING
          RETURNING id INTO v_task_id;

          IF v_task_id IS NULL THEN
            SELECT * INTO v_existing_task
            FROM public.tasks AS task
            WHERE task.origin_kind = 'case_note'
              AND task.origin_note_id = v_note.id;
            IF v_existing_task.id IS NOT NULL
               AND v_existing_task.org_id = v_note.org_id
               AND v_existing_task.client_id = v_client_id
               AND v_existing_task.matter_id = v_note.matter_id
               AND v_existing_task.document_id IS NOT DISTINCT FROM v_note.document_id THEN
              v_disposition := 'existing_task';
              v_task_id := v_existing_task.id;
            ELSE
              v_disposition := 'existing_task_lineage_conflict';
            END IF;
          ELSE
            -- Legacy notes do not retain a trustworthy historical completion
            -- actor/time. The migration is the trusted producer: it writes a
            -- system-owned task.created event/outbox pair, preserves the known
            -- current state on Task, and never treats the old author as an
            -- active Activity actor.
            v_activity_idempotency_key := 'task.legacy_note_backfill:' || v_note.id::text;
            PERFORM public.append_activity_event(
              v_note.org_id, 'task.created', 1::smallint,
              'system', NULL, 'Legacy Task migration',
              'task', v_task_id, v_client_id, v_note.matter_id,
              'Task', 'Task migrated from legacy note', '{}'::jsonb,
              'task', v_task_id, NULL, NULL, NULL,
              v_activity_idempotency_key, v_note.created_at
            );
            v_disposition := 'migrated';
          END IF;
        END IF;
      END IF;
    END IF;

    INSERT INTO public.task_legacy_note_backfill_diagnostics (
      source_note_id, source_org_id, disposition, task_id
    ) VALUES (v_note.id, v_note.org_id, v_disposition, v_task_id);

    RETURN QUERY SELECT v_disposition, 1::bigint;
  END LOOP;
END $$;

ALTER TABLE public.task_legacy_note_backfill_diagnostics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_legacy_note_backfill_diagnostics FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.task_legacy_note_backfill_diagnostics,
  public.task_legacy_note_backfill_reports FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.backfill_legacy_note_action_items(uuid, integer)
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.task_legacy_note_backfill_diagnostics,
  public.task_legacy_note_backfill_reports TO service_role;
GRANT EXECUTE ON FUNCTION public.backfill_legacy_note_action_items(uuid, integer)
  TO service_role;

COMMENT ON TABLE public.task_legacy_note_backfill_diagnostics IS
  'Service-only, content-free terminal disposition for each historic action-item note. Existing Task origins are diagnostics only and are never overwritten.';
COMMENT ON VIEW public.task_legacy_note_backfill_reports IS
  'Service-only aggregate report for the additive historic action-item Task migration; no note content or source identifiers.';
COMMENT ON FUNCTION public.backfill_legacy_note_action_items(uuid, integer) IS
  'Service-only, organisation-scoped, SKIP LOCKED legacy note action-item Task backfill. It emits system-owned task.created Activity/outbox parity for newly migrated Tasks.';

COMMIT;
