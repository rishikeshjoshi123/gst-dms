-- Audited, capability-checked removal for legacy case notes.

ALTER TABLE public.case_notes
  ADD COLUMN deleted_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  ADD COLUMN deletion_kind text,
  ADD COLUMN deletion_reason text;

UPDATE public.case_notes
SET deleted_by = author_id,
    deletion_kind = 'legacy',
    deletion_reason = 'Removed before audited note removal was introduced.'
WHERE deleted_at IS NOT NULL;

ALTER TABLE public.case_notes
  ADD CONSTRAINT case_notes_removal_audit_consistent CHECK (
    (deleted_at IS NULL AND deleted_by IS NULL AND deletion_kind IS NULL AND deletion_reason IS NULL)
    OR
    (deleted_at IS NOT NULL AND deleted_by IS NOT NULL AND deletion_kind = 'author' AND deletion_reason IS NULL)
    OR
    (deleted_at IS NOT NULL AND deleted_by IS NOT NULL AND deletion_kind IN ('moderation', 'legacy')
      AND length(btrim(deletion_reason)) BETWEEN 8 AND 500)
  );

CREATE OR REPLACE FUNCTION public.case_notes_protect_removal_contract()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF current_user = 'postgres' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'case notes may only be purged by the governed lifecycle'
      USING ERRCODE = '42501';
  END IF;

  IF OLD.deleted_at IS NOT NULL
     OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
     OR NEW.deleted_by IS DISTINCT FROM OLD.deleted_by
     OR NEW.deletion_kind IS DISTINCT FROM OLD.deletion_kind
     OR NEW.deletion_reason IS DISTINCT FROM OLD.deletion_reason THEN
    RAISE EXCEPTION 'case notes may only be removed through remove_case_note'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS case_notes_protect_removal_contract ON public.case_notes;
CREATE TRIGGER case_notes_protect_removal_contract
  BEFORE UPDATE OR DELETE ON public.case_notes
  FOR EACH ROW EXECUTE FUNCTION public.case_notes_protect_removal_contract();

CREATE OR REPLACE FUNCTION public.remove_case_note(
  p_note_id uuid,
  p_moderation_reason text DEFAULT NULL
)
RETURNS TABLE (
  code text,
  matter_id uuid,
  document_id uuid,
  removed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_membership public.organisation_memberships%ROWTYPE;
  v_note public.case_notes%ROWTYPE;
  v_matter_id uuid;
  v_is_owner boolean := false;
  v_removed_at timestamptz := statement_timestamp();
  v_reason text := NULLIF(btrim(p_moderation_reason), '');
BEGIN
  IF v_actor IS NULL OR p_note_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE membership.state = 'active')
  INTO v_current_count, v_active_count
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor
    AND membership.state IN ('active', 'suspended');

  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT * INTO v_membership
  FROM public.organisation_memberships AS membership
  WHERE membership.user_id = v_actor AND membership.state = 'active'
  FOR SHARE;

  IF v_membership.id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT note.matter_id INTO v_matter_id
  FROM public.case_notes AS note
  WHERE note.id = p_note_id
    AND note.org_id = v_membership.org_id;

  IF v_matter_id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  PERFORM 1
  FROM public.matters AS matter
  WHERE matter.id = v_matter_id
    AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active'
    AND matter.deleted_at IS NULL
  FOR SHARE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT note.* INTO v_note
  FROM public.case_notes AS note
  WHERE note.id = p_note_id
    AND note.org_id = v_membership.org_id
    AND note.matter_id = v_matter_id
  FOR UPDATE;

  IF v_note.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT COALESCE(organisation.owner_membership_id = v_membership.id, false)
  INTO v_is_owner
  FROM public.organisations AS organisation
  WHERE organisation.id = v_membership.org_id;

  IF v_note.author_id = v_actor THEN
    IF v_reason IS NOT NULL THEN
      RETURN QUERY SELECT 'reason_not_allowed'::text, v_note.matter_id, v_note.document_id, v_note.deleted_at;
      RETURN;
    END IF;
  ELSIF NOT (v_is_owner OR v_membership.role = 'admin') THEN
    RETURN QUERY SELECT 'not_allowed'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  ELSIF v_reason IS NULL OR length(v_reason) NOT BETWEEN 8 AND 500 THEN
    RETURN QUERY SELECT 'reason_required'::text, v_note.matter_id, v_note.document_id, v_note.deleted_at;
    RETURN;
  END IF;

  IF v_note.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'already_removed'::text, v_note.matter_id, v_note.document_id, v_note.deleted_at;
    RETURN;
  END IF;

  UPDATE public.case_notes AS note
  SET deleted_at = v_removed_at,
      deleted_by = v_actor,
      deletion_kind = CASE WHEN v_note.author_id = v_actor THEN 'author' ELSE 'moderation' END,
      deletion_reason = CASE WHEN v_note.author_id = v_actor THEN NULL ELSE v_reason END
  WHERE note.id = v_note.id;

  RETURN QUERY SELECT 'ok'::text, v_note.matter_id, v_note.document_id, v_removed_at;
END;
$$;

REVOKE ALL ON FUNCTION public.case_notes_protect_removal_contract() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.remove_case_note(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.remove_case_note(uuid, text) TO authenticated;

COMMENT ON FUNCTION public.remove_case_note(uuid, text) IS
  'Authenticated note-removal command. Revalidates one active membership and active Matter while locked; authors remove their own notes, while owners/admins must supply an audit reason.';
