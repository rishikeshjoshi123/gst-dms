-- Canonical global Inbox placement, discard, and preview boundaries.
-- Legacy staged_documents remain behind their separate compatibility adapter.
BEGIN;

ALTER TABLE public.document_command_receipts
  DROP CONSTRAINT document_command_receipts_command_kind_check;
ALTER TABLE public.document_command_receipts
  ADD CONSTRAINT document_command_receipts_command_kind_check
  CHECK (command_kind IN ('validate_asset','create_metadata','assign_intake','auto_assign_intake','attach_intake','replace_version','discard_intake'));

-- A ready intake owns an immutable private asset but does not yet own a
-- document version. Resolve its object only after tenant and capability checks;
-- callers cannot turn an arbitrary bucket/key into a signed URL.
CREATE OR REPLACE FUNCTION public.get_intake_item_read_grant(p_intake_id uuid)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN i.id IS NULL THEN 'not_found' ELSE 'ok' END,
         CASE WHEN i.id IS NULL THEN NULL ELSE a.bucket_id END,
         CASE WHEN i.id IS NULL THEN NULL ELSE a.object_key END
  FROM (SELECT org_id FROM public.get_my_organisation_context()
        WHERE state='active' AND 'document.view'=ANY(capabilities) LIMIT 1) AS actor
  LEFT JOIN public.intake_items AS i ON i.id=p_intake_id AND i.org_id=actor.org_id
  LEFT JOIN public.file_assets AS a ON a.id=i.asset_id AND a.org_id=actor.org_id
  WHERE i.state='ready'
    AND a.availability='available'
    AND a.detected_mime_type='application/pdf'
    AND a.storage_deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION public.discard_intake_item(p_intake_id uuid,p_idempotency uuid)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; i public.intake_items%ROWTYPE; a public.file_assets%ROWTYPE;
  prior public.document_command_receipts%ROWTYPE;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.intake.discard') LIMIT 1;
  IF x.org_id IS NULL OR p_intake_id IS NULL OR p_idempotency IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO prior FROM public.document_command_receipts
    WHERE org_id=x.org_id AND actor_user_id=x.actor_id
      AND command_kind='discard_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code; RETURN; END IF;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF i.state='assigned' OR EXISTS (SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN
    RETURN QUERY SELECT 'intake_assigned'::text; RETURN;
  END IF;
  IF i.state='discarded' THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
      VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'already_discarded');
    RETURN QUERY SELECT 'already_discarded'::text; RETURN;
  END IF;
  SELECT * INTO a FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF a.id IS NULL THEN RETURN QUERY SELECT 'asset_not_found'::text; RETURN; END IF;
  UPDATE public.intake_items
  SET state='discarded',discarded_at=now(),failed_at=NULL,expired_at=NULL,
      updated_at=now(),failure_code='discarded'
  WHERE id=i.id;
  -- Storage deletion remains separately leased and only tombstones after the
  -- provider confirms it. This makes discard safe under retries and failures.
  UPDATE public.file_assets SET availability='failed',failed_at=coalesce(failed_at,now()),failure_code='discarded'
    WHERE id=a.id AND NOT EXISTS (SELECT 1 FROM public.document_versions dv WHERE dv.asset_id=a.id);
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
    VALUES(x.org_id,x.actor_id,'discard_intake',p_idempotency,i.id,'ok');
  PERFORM public.document_materialization_safe_event(x.org_id,i.id,'intake.discarded.v1',
    'intake.discard.'||i.id::text,jsonb_build_object('intake_id',i.id::text,'result_code','discarded'));
  RETURN QUERY SELECT 'ok'::text;
END $$;

REVOKE ALL ON FUNCTION public.get_intake_item_read_grant(uuid), public.discard_intake_item(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_intake_item_read_grant(uuid), public.discard_intake_item(uuid,uuid) TO authenticated;
COMMIT;
