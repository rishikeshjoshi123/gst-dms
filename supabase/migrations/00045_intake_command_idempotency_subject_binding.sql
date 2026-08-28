-- Bind idempotency receipts to the Intake aggregate they authorise.
BEGIN;

-- Assignment is observable independently from subsequent document processing.
-- A transition trigger covers both user-directed global placement and the
-- existing trusted intended-matter auto-assignment without duplicate events.
CREATE OR REPLACE FUNCTION public.emit_intake_assigned_event()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE assignment_row public.intake_item_assignments%ROWTYPE;
BEGIN
  IF NEW.state='assigned' AND OLD.state IS DISTINCT FROM 'assigned' THEN
    SELECT * INTO assignment_row FROM public.intake_item_assignments
      WHERE intake_item_id=NEW.id AND org_id=NEW.org_id ORDER BY created_at DESC LIMIT 1;
    IF assignment_row.id IS NULL THEN RAISE EXCEPTION 'assigned intake requires an assignment record'; END IF;
    PERFORM public.document_materialization_safe_event(NEW.org_id,NEW.id,'intake.assigned.v1',
      'intake.assigned.'||NEW.id::text,
      jsonb_build_object('intake_id',NEW.id::text,'document_id',assignment_row.document_id::text,'document_version_id',assignment_row.document_version_id::text));
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS intake_items_emit_assigned_event ON public.intake_items;
CREATE TRIGGER intake_items_emit_assigned_event
  AFTER UPDATE OF state ON public.intake_items
  FOR EACH ROW EXECUTE FUNCTION public.emit_intake_assigned_event();

CREATE OR REPLACE FUNCTION public.assign_intake_to_new_document(p_intake_id uuid,p_matter_id uuid,p_display_title text,p_expected_intake_uploader uuid,p_idempotency uuid)
RETURNS TABLE(code text, document_id uuid, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; i public.intake_items%ROWTYPE; d uuid; v uuid; rev bigint; prior public.document_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO x FROM public.document_materialization_actor('document.intake.assign') LIMIT 1;
 IF x.org_id IS NULL OR p_idempotency IS NULL OR p_display_title IS NULL OR char_length(p_display_title) NOT BETWEEN 1 AND 255 OR p_display_title~'[[:cntrl:]]' THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='assign_intake' AND idempotency_key=p_idempotency;
 IF prior.id IS NOT NULL THEN
   IF prior.subject_id IS DISTINCT FROM p_intake_id THEN RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid,NULL::uuid,NULL::bigint; ELSE RETURN QUERY SELECT prior.result_code,prior.document_id,prior.document_version_id,prior.lifecycle_revision; END IF;
   RETURN;
 END IF;
 SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
 IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.uploaded_by IS NULL THEN RETURN QUERY SELECT 'uploader_mismatch'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=p_matter_id AND m.org_id=x.org_id AND m.status='active' AND m.deleted_at IS NULL) THEN RETURN QUERY SELECT 'invalid_matter'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 INSERT INTO public.documents AS document_record (org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by) VALUES(x.org_id,p_matter_id,p_display_title,'upload','active','metadata_only','placed',NULL,x.actor_id) RETURNING document_record.id INTO d;
 v:=public.document_materialization_insert_version(x.org_id,d,i.id,x.actor_id,NULL);
 UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions AS dv WHERE dv.id=v),effective_size_bytes=(SELECT asset.byte_size FROM public.file_assets AS asset JOIN public.document_versions AS dv ON dv.asset_id=asset.id WHERE dv.id=v) WHERE document_record.id=d RETURNING document_record.lifecycle_revision INTO rev;
 INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d,v,x.actor_id); UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.intake_assigned','document',d,'Assigned validated intake to a new document',jsonb_build_object('document_id',d::text,'version_id',v::text));
 INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'assign_intake',p_idempotency,i.id,'ok',d,v,rev);
 PERFORM public.document_materialization_safe_event(x.org_id,d,'document.processing_requested.v1','document.processing.assign.'||v::text,jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text));
 RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

CREATE OR REPLACE FUNCTION public.discard_intake_item(p_intake_id uuid,p_idempotency uuid)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; i public.intake_items%ROWTYPE; a public.file_assets%ROWTYPE; prior public.document_command_receipts%ROWTYPE;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.intake.discard') LIMIT 1;
  IF x.org_id IS NULL OR p_intake_id IS NULL OR p_idempotency IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='discard_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM p_intake_id THEN RETURN QUERY SELECT 'idempotency_subject_mismatch'::text; ELSE RETURN QUERY SELECT prior.result_code; END IF;
    RETURN;
  END IF;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF i.state='discarded' THEN INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code) VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'already_discarded'); RETURN QUERY SELECT 'already_discarded'::text; RETURN; END IF;
  IF i.state<>'ready' OR EXISTS (SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_not_discardable'::text; RETURN; END IF;
  SELECT * INTO a FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF a.id IS NULL OR a.availability<>'available' THEN RETURN QUERY SELECT 'intake_not_discardable'::text; RETURN; END IF;
  UPDATE public.intake_items SET state='discarded',discarded_at=now(),updated_at=now(),failure_code='discarded' WHERE id=i.id;
  UPDATE public.file_assets SET availability='failed',validated_at=NULL,failed_at=now(),failure_code='discarded' WHERE id=a.id AND NOT EXISTS (SELECT 1 FROM public.document_versions dv WHERE dv.asset_id=a.id);
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code) VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'ok');
  PERFORM public.document_materialization_safe_event(x.org_id,i.id,'intake.discarded.v1','intake.discard.'||i.id::text,jsonb_build_object('intake_id',i.id::text,'result_code','discarded'));
  RETURN QUERY SELECT 'ok'::text;
END $$;
REVOKE ALL ON FUNCTION public.emit_intake_assigned_event() FROM PUBLIC, anon, authenticated;
COMMIT;
