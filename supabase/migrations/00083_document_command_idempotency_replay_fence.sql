-- Serialize replay decisions for document/intake commands and bind a receipt
-- to the complete command subject.  The receipt schema intentionally exposes
-- one UUID subject field, so attach and replace store a deterministic UUID
-- fingerprint of their (document, intake) pair in that existing field.
BEGIN;

CREATE OR REPLACE FUNCTION public.attach_intake_to_document(
  p_document_id uuid, p_intake_id uuid, p_expected_revision bigint,
  p_expected_intake_uploader uuid, p_idempotency uuid)
RETURNS TABLE(code text, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  x record;
  d public.documents%ROWTYPE;
  i public.intake_items%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  v uuid;
  rev bigint;
  prior public.document_command_receipts%ROWTYPE;
  command_subject uuid;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.version.attach') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::bigint; RETURN;
  END IF;

  command_subject := (
    substr(pg_catalog.md5('document-command-subject:attach_intake:' || p_document_id::text || ':' || p_intake_id::text), 1, 8) || '-' ||
    substr(pg_catalog.md5('document-command-subject:attach_intake:' || p_document_id::text || ':' || p_intake_id::text), 9, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:attach_intake:' || p_document_id::text || ':' || p_intake_id::text), 13, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:attach_intake:' || p_document_id::text || ':' || p_intake_id::text), 17, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:attach_intake:' || p_document_id::text || ':' || p_intake_id::text), 21, 12)
  )::uuid;

  -- Same actor/key calls must decide replay before they can contend for a
  -- target, Intake, or exact-PDF fence.  That makes a waiter replay the first
  -- result instead of observing the Intake after it was consumed.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text),
    pg_catalog.hashtext(x.actor_id::text || ':attach_intake:' || p_idempotency::text)
  );
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id
    AND command_kind='attach_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM command_subject THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text, NULL::uuid, NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code, prior.document_version_id, prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF d.id IS NULL OR i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF d.record_state<>'active' THEN RETURN QUERY SELECT 'record_trashed'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF d.lifecycle_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision'::text,NULL::uuid,d.lifecycle_revision; RETURN; END IF;
  IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF asset.id IS NULL OR asset.sha256 IS NULL OR asset.sha256 !~ '^[0-9a-f]{64}$' THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(x.org_id::text), pg_catalog.hashtext(asset.sha256));
  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;

  -- The key fence normally makes this redundant; retain the re-read under the
  -- resource/SHA fences so a future caller with the same durable receipt is
  -- still resolved before any stale state result.
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id
    AND command_kind='attach_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM command_subject THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text, NULL::uuid, NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code, prior.document_version_id, prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  IF d.id IS NULL OR i.id IS NULL OR asset.id IS NULL OR i.state<>'ready'
     OR d.record_state<>'active' OR d.lifecycle_revision<>p_expected_revision
     OR d.content_availability<>'metadata_only' OR d.current_version_id IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id)
     OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN
    RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.org_id=x.org_id AND existing.asset_id=asset.id AND existing.document_id<>d.id AND existing.validation_state='valid' AND existing.state IN ('current','superseded')) THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
    VALUES(x.org_id,x.actor_id,'attach_intake',p_idempotency,command_subject,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,NULL);
  UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),effective_size_bytes=(SELECT source.byte_size FROM public.file_assets source JOIN public.document_versions dv ON dv.asset_id=source.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.file_attached','document',d.id,'Attached validated source to document',jsonb_build_object('document_id',d.id::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'attach_intake',p_idempotency,command_subject,'ok',d.id,v,rev);
  PERFORM public.document_materialization_safe_event(x.org_id,d.id,'document.processing_requested.v1','document.processing.attach.'||v::text,jsonb_build_object('document_id',d.id::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,v,rev;
END $$;

CREATE OR REPLACE FUNCTION public.replace_document_version(
  p_document_id uuid, p_intake_id uuid, p_expected_revision bigint, p_replacement_reason text,
  p_expected_intake_uploader uuid, p_idempotency uuid)
RETURNS TABLE(code text, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  x record;
  d public.documents%ROWTYPE;
  i public.intake_items%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  old public.document_versions%ROWTYPE;
  v uuid;
  rev bigint;
  prior public.document_command_receipts%ROWTYPE;
  command_subject uuid;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.version.replace') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL OR p_replacement_reason IS NULL OR char_length(btrim(p_replacement_reason)) NOT BETWEEN 1 AND 500 OR p_replacement_reason~'[[:cntrl:]]' THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint; RETURN; END IF;

  command_subject := (
    substr(pg_catalog.md5('document-command-subject:replace_version:' || p_document_id::text || ':' || p_intake_id::text), 1, 8) || '-' ||
    substr(pg_catalog.md5('document-command-subject:replace_version:' || p_document_id::text || ':' || p_intake_id::text), 9, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:replace_version:' || p_document_id::text || ':' || p_intake_id::text), 13, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:replace_version:' || p_document_id::text || ':' || p_intake_id::text), 17, 4) || '-' ||
    substr(pg_catalog.md5('document-command-subject:replace_version:' || p_document_id::text || ':' || p_intake_id::text), 21, 12)
  )::uuid;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text),
    pg_catalog.hashtext(x.actor_id::text || ':replace_version:' || p_idempotency::text)
  );
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id
    AND command_kind='replace_version' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM command_subject THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text, NULL::uuid, NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code, prior.document_version_id, prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF d.id IS NULL OR i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF d.record_state<>'active' THEN RETURN QUERY SELECT 'record_trashed'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF d.lifecycle_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision'::text,NULL::uuid,d.lifecycle_revision; RETURN; END IF;
  IF i.state<>'ready' OR i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF asset.id IS NULL OR asset.sha256 IS NULL OR asset.sha256 !~ '^[0-9a-f]{64}$' THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(x.org_id::text), pg_catalog.hashtext(asset.sha256));
  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO old FROM public.document_versions WHERE id=d.current_version_id AND document_id=d.id FOR UPDATE;
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id
    AND command_kind='replace_version' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM command_subject THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text, NULL::uuid, NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code, prior.document_version_id, prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  IF d.id IS NULL OR i.id IS NULL OR asset.id IS NULL OR old.id IS NULL OR i.state<>'ready'
     OR d.record_state<>'active' OR d.lifecycle_revision<>p_expected_revision
     OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  -- The unique document/asset constraint makes an already retained version a
  -- no-op, not a cross-document duplicate. This preserves the existing
  -- same-document history contract while avoiding a raw unique violation.
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.document_id=d.id AND existing.asset_id=asset.id) THEN RETURN QUERY SELECT 'same_asset'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.org_id=x.org_id AND existing.asset_id=asset.id AND existing.document_id<>d.id AND existing.validation_state='valid' AND existing.state IN ('current','superseded')) THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code) VALUES(x.org_id,x.actor_id,'replace_version',p_idempotency,command_subject,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  UPDATE public.document_versions AS prior_version SET state='superseded',superseded_at=now() WHERE prior_version.id=old.id;
  v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,btrim(p_replacement_reason));
  UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),effective_size_bytes=(SELECT source.byte_size FROM public.file_assets source JOIN public.document_versions dv ON dv.asset_id=source.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.version_replaced','document',d.id,'Replaced document source version',jsonb_build_object('document_id',d.id::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'replace_version',p_idempotency,command_subject,'ok',d.id,v,rev);
  PERFORM public.document_materialization_safe_event(x.org_id,d.id,'document.processing_requested.v1','document.processing.replace.'||v::text,jsonb_build_object('document_id',d.id::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,v,rev;
END $$;

COMMENT ON FUNCTION public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid) IS
  'Authenticated attachment with actor/key replay serialization, full document/Intake receipt binding, and typed cross-document exact-PDF duplicate rejection.';
COMMENT ON FUNCTION public.replace_document_version(uuid,uuid,bigint,text,uuid,uuid) IS
  'Authenticated replacement with actor/key replay serialization, full document/Intake receipt binding, same-document history, and typed cross-document exact-PDF duplicate rejection.';
COMMIT;
