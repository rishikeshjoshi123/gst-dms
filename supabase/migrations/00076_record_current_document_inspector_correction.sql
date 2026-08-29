BEGIN;

CREATE FUNCTION public.record_current_document_inspector_correction(
  p_org_id uuid, p_document_id uuid, p_document_version_id uuid,
  p_document_field_candidate_id uuid, p_field_path text,
  p_replacement_value jsonb, p_actor_user_id uuid, p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  effective_candidate_id uuid;
BEGIN
  SELECT * INTO document_row FROM public.documents
  WHERE id=p_document_id AND org_id=p_org_id AND deleted_at IS NULL
    AND record_state='active'::public.document_record_state FOR UPDATE;
  IF document_row.id IS NULL OR document_row.current_version_id IS DISTINCT FROM p_document_version_id THEN
    RAISE EXCEPTION 'current document version is unavailable';
  END IF;
  SELECT * INTO version_row FROM public.document_versions
  WHERE id=p_document_version_id AND org_id=p_org_id AND document_id=p_document_id FOR UPDATE;
  IF version_row.id IS NULL OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RAISE EXCEPTION 'current document version is unavailable';
  END IF;
  SELECT winning_document_field_candidate_id INTO effective_candidate_id
  FROM public.document_effective_metadata
  WHERE org_id=p_org_id AND document_id=p_document_id AND document_version_id=p_document_version_id
    AND field_path=p_field_path AND winning_document_field_candidate_id=p_document_field_candidate_id
  FOR KEY SHARE;
  IF effective_candidate_id IS NULL THEN
    RAISE EXCEPTION 'current effective field candidate is unavailable';
  END IF;
  RETURN public.record_document_field_decision(
    p_document_field_candidate_id, 'corrected'::public.document_field_decision_action,
    p_replacement_value, 'Inspector correction', p_actor_user_id, p_idempotency_key);
END $$;

REVOKE ALL ON FUNCTION public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text) TO service_role;
COMMENT ON FUNCTION public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text) IS
  'Service-only atomic current-effective-candidate correction command for the document inspector.';
COMMIT;
