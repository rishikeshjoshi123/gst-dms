-- Service-only continuation for intended matter uploads after trusted validation.
BEGIN;

ALTER TABLE public.document_command_receipts
  DROP CONSTRAINT document_command_receipts_command_kind_check;
ALTER TABLE public.document_command_receipts
  ADD CONSTRAINT document_command_receipts_command_kind_check
  CHECK (command_kind IN ('validate_asset','create_metadata','assign_intake','auto_assign_intake','attach_intake','replace_version'));

CREATE OR REPLACE FUNCTION public.auto_assign_intended_matter_intake(p_intake_id uuid,p_validation_event_id uuid)
RETURNS TABLE(code text, document_id uuid, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE i public.intake_items%ROWTYPE; prior public.document_command_receipts%ROWTYPE;
  validation_event public.outbox_events%ROWTYPE; d uuid; v uuid; rev bigint;
BEGIN
  IF p_intake_id IS NULL OR p_validation_event_id IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  SELECT * INTO validation_event FROM public.outbox_events
    WHERE id=p_validation_event_id AND event_kind='document.intake_validated.v1'
      AND aggregate_type='document' AND aggregate_id=p_intake_id FOR UPDATE;
  IF validation_event.id IS NULL THEN
    RETURN QUERY SELECT 'invalid_event'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  SELECT * INTO i FROM public.intake_items
    WHERE id=p_intake_id AND org_id=validation_event.org_id FOR UPDATE;
  IF i.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  IF i.intended_matter_id IS NULL THEN
    RETURN QUERY SELECT 'not_intended'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  SELECT * INTO prior FROM public.document_command_receipts
    WHERE org_id=i.org_id AND actor_user_id=i.uploaded_by AND command_kind='auto_assign_intake'
      AND idempotency_key=p_validation_event_id;
  IF prior.id IS NOT NULL THEN
    RETURN QUERY SELECT prior.result_code,prior.document_id,prior.document_version_id,prior.lifecycle_revision; RETURN;
  END IF;
  IF i.uploaded_by IS NULL OR i.state<>'ready' OR EXISTS(
      SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id
    ) OR NOT EXISTS (
      SELECT 1 FROM public.matters m
      WHERE m.id=i.intended_matter_id AND m.org_id=i.org_id AND m.status='active' AND m.deleted_at IS NULL
    ) OR NOT EXISTS (
      SELECT 1 FROM public.organisation_memberships m
      LEFT JOIN public.organisations o ON o.id=m.org_id
      WHERE m.org_id=i.org_id AND m.user_id=i.uploaded_by AND m.state='active'
        AND (m.role IN ('admin','associate') OR o.owner_membership_id=m.id)
    ) THEN
    RETURN QUERY SELECT 'not_auto_assignable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  INSERT INTO public.documents AS document_record
    (org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES
    (i.org_id,i.intended_matter_id,(SELECT declared_filename FROM public.upload_sessions WHERE id=i.upload_session_id AND org_id=i.org_id),
      'upload','active','metadata_only','placed',NULL,i.uploaded_by)
  RETURNING document_record.id INTO d;
  v:=public.document_materialization_insert_version(i.org_id,d,i.id,i.uploaded_by,NULL);
  UPDATE public.documents AS document_record
  SET current_version_id=v,content_availability='source_attached',
    effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),
    effective_size_bytes=(SELECT asset.byte_size FROM public.file_assets asset JOIN public.document_versions dv ON dv.asset_id=asset.id WHERE dv.id=v)
  WHERE document_record.id=d RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by)
    VALUES(i.org_id,i.id,d,v,i.uploaded_by);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata)
    VALUES(i.org_id,i.uploaded_by,'document.intake_assigned','document',d,'Assigned validated intake to its intended matter',jsonb_build_object('document_id',d::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision)
    VALUES(i.org_id,i.uploaded_by,'auto_assign_intake',p_validation_event_id,i.id,'ok',d,v,rev);
  PERFORM public.document_materialization_safe_event(i.org_id,d,'document.processing_requested.v1','document.processing.intended_assign.'||v::text,jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

REVOKE ALL ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) TO service_role;
COMMIT;
