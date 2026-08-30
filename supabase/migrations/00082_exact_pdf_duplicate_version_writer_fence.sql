-- Close the remaining exact-PDF materialisation race.
--
-- Every production authority that can create a valid current/superseded
-- document version takes this organisation/SHA fence before it decides that
-- the asset may be referenced.  The fence is intentionally about *logical
-- documents*: a documented version history on the same document remains
-- possible, while a second document may not materialise the same PDF.
BEGIN;

-- This is a defence-in-depth boundary for the service-only, backfill-aware
-- insert primitive as well as its user and command callers below.  It keeps
-- the legacy staged-backfill filename exception from 00049, but refuses an
-- attempted cross-document materialisation even if a future service command
-- forgets to perform the typed preflight used by the public commands.
CREATE OR REPLACE FUNCTION public.document_materialization_insert_version(
  p_org uuid, p_document uuid, p_intake uuid, p_actor uuid, p_reason text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_intake public.intake_items%ROWTYPE;
  v_asset public.file_assets%ROWTYPE;
  v_name text;
  v_number integer;
  v_version uuid;
BEGIN
  SELECT * INTO v_intake
  FROM public.intake_items
  WHERE id = p_intake AND org_id = p_org
  FOR UPDATE;
  SELECT * INTO v_asset
  FROM public.file_assets
  WHERE id = v_intake.asset_id AND org_id = p_org
  FOR UPDATE;
  IF v_intake.id IS NULL OR v_intake.state <> 'ready' OR v_asset.id IS NULL
     OR v_asset.availability <> 'available'
     OR v_asset.detected_mime_type <> 'application/pdf'
     OR v_asset.validated_page_count IS NULL
     OR v_asset.sha256 IS NULL OR v_asset.sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'intake is not a ready validated PDF';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_org::text), pg_catalog.hashtext(v_asset.sha256)
  );
  SELECT * INTO v_intake
  FROM public.intake_items
  WHERE id = p_intake AND org_id = p_org
  FOR UPDATE;
  SELECT * INTO v_asset
  FROM public.file_assets
  WHERE id = v_intake.asset_id AND org_id = p_org
  FOR UPDATE;
  IF v_intake.id IS NULL OR v_intake.state <> 'ready' OR v_asset.id IS NULL
     OR v_asset.availability <> 'available'
     OR v_asset.detected_mime_type <> 'application/pdf'
     OR v_asset.validated_page_count IS NULL
     OR v_asset.sha256 IS NULL OR v_asset.sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'intake is not a ready validated PDF';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.document_versions AS existing
    WHERE existing.org_id = p_org
      AND existing.asset_id = v_asset.id
      AND existing.document_id <> p_document
      AND existing.validation_state = 'valid'
      AND existing.state IN ('current', 'superseded')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001',
      MESSAGE = 'cross-document duplicate PDF reference';
  END IF;

  SELECT declared_filename INTO v_name
  FROM public.upload_sessions
  WHERE id = v_intake.upload_session_id AND org_id = p_org;
  IF v_name IS NULL AND EXISTS (
    SELECT 1
    FROM public.staged_document_backfill_items AS map
    WHERE map.org_id = p_org AND map.canonical_intake_item_id = v_intake.id
      AND map.outcome = 'transfer_pending' AND map.transfer_completed_at IS NOT NULL
  ) THEN
    v_name := 'legacy-staged-document.pdf';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'trusted upload filename is unavailable';
  END IF;
  SELECT coalesce(max(version_number), 0) + 1 INTO v_number
  FROM public.document_versions
  WHERE document_id = p_document;
  INSERT INTO public.document_versions AS document_version
    (org_id, document_id, asset_id, version_number, original_filename, page_count,
     validation_state, state, replacement_reason, created_by, validated_at, promoted_at)
  VALUES
    (p_org, p_document, v_asset.id, v_number, v_name, v_asset.validated_page_count,
     'valid', 'current', p_reason, p_actor, now(), now())
  RETURNING document_version.id INTO v_version;
  RETURN v_version;
END $$;

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
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.version.attach') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::bigint; RETURN;
  END IF;
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='attach_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    RETURN QUERY SELECT prior.result_code, prior.document_version_id, prior.lifecycle_revision; RETURN;
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
  IF d.id IS NULL OR i.id IS NULL OR asset.id IS NULL OR i.state<>'ready'
     OR d.record_state<>'active' OR d.lifecycle_revision<>p_expected_revision
     OR d.content_availability<>'metadata_only' OR d.current_version_id IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id)
     OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN
    RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.org_id=x.org_id AND existing.asset_id=asset.id AND existing.document_id<>d.id AND existing.validation_state='valid' AND existing.state IN ('current','superseded')) THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
    VALUES(x.org_id,x.actor_id,'attach_intake',p_idempotency,d.id,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,NULL);
  UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),effective_size_bytes=(SELECT source.byte_size FROM public.file_assets source JOIN public.document_versions dv ON dv.asset_id=source.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.file_attached','document',d.id,'Attached validated source to document',jsonb_build_object('document_id',d.id::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'attach_intake',p_idempotency,d.id,'ok',d.id,v,rev);
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
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.version.replace') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL OR p_replacement_reason IS NULL OR char_length(btrim(p_replacement_reason)) NOT BETWEEN 1 AND 500 OR p_replacement_reason~'[[:cntrl:]]' THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='replace_version' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_version_id,prior.lifecycle_revision; RETURN; END IF;
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
  IF d.id IS NULL OR i.id IS NULL OR asset.id IS NULL OR old.id IS NULL OR i.state<>'ready'
     OR d.record_state<>'active' OR d.lifecycle_revision<>p_expected_revision
     OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  -- The unique document/asset constraint makes an already retained version a
  -- no-op, not a cross-document duplicate. This preserves the existing
  -- same-document history contract while avoiding a raw unique violation.
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.document_id=d.id AND existing.asset_id=asset.id) THEN RETURN QUERY SELECT 'same_asset'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.org_id=x.org_id AND existing.asset_id=asset.id AND existing.document_id<>d.id AND existing.validation_state='valid' AND existing.state IN ('current','superseded')) THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code) VALUES(x.org_id,x.actor_id,'replace_version',p_idempotency,d.id,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  UPDATE public.document_versions AS prior_version SET state='superseded',superseded_at=now() WHERE prior_version.id=old.id;
  v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,btrim(p_replacement_reason));
  UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),effective_size_bytes=(SELECT source.byte_size FROM public.file_assets source JOIN public.document_versions dv ON dv.asset_id=source.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.version_replaced','document',d.id,'Replaced document source version',jsonb_build_object('document_id',d.id::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'replace_version',p_idempotency,d.id,'ok',d.id,v,rev);
  PERFORM public.document_materialization_safe_event(x.org_id,d.id,'document.processing_requested.v1','document.processing.replace.'||v::text,jsonb_build_object('document_id',d.id::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,v,rev;
END $$;

CREATE OR REPLACE FUNCTION public.auto_assign_intended_matter_intake(p_intake_id uuid,p_validation_event_id uuid)
RETURNS TABLE(code text, document_id uuid, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  i public.intake_items%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  prior public.document_command_receipts%ROWTYPE;
  validation_event public.outbox_events%ROWTYPE;
  d uuid;
  v uuid;
  rev bigint;
BEGIN
  IF p_intake_id IS NULL OR p_validation_event_id IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO validation_event FROM public.outbox_events WHERE id=p_validation_event_id AND event_kind='document.intake_validated.v1' AND aggregate_type='document' AND aggregate_id=p_intake_id FOR UPDATE;
  IF validation_event.id IS NULL THEN RETURN QUERY SELECT 'invalid_event'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=validation_event.org_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF i.intended_matter_id IS NULL THEN RETURN QUERY SELECT 'not_intended'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=i.org_id AND actor_user_id=i.uploaded_by AND command_kind='auto_assign_intake' AND idempotency_key=p_validation_event_id;
  IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_id,prior.document_version_id,prior.lifecycle_revision; RETURN; END IF;
  IF i.uploaded_by IS NULL OR i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=i.org_id AND ia.intake_item_id=i.id) OR NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=i.intended_matter_id AND m.org_id=i.org_id AND m.status='active' AND m.deleted_at IS NULL AND m.record_state='active') OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships m LEFT JOIN public.organisations o ON o.id=m.org_id WHERE m.org_id=i.org_id AND m.user_id=i.uploaded_by AND m.state='active' AND (m.role IN ('admin','associate') OR o.owner_membership_id=m.id)) THEN RETURN QUERY SELECT 'not_auto_assignable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=i.org_id FOR UPDATE;
  IF asset.id IS NULL OR asset.sha256 IS NULL OR asset.sha256 !~ '^[0-9a-f]{64}$' THEN RETURN QUERY SELECT 'not_auto_assignable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(i.org_id::text), pg_catalog.hashtext(asset.sha256));
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=validation_event.org_id FOR UPDATE;
  SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=i.org_id FOR UPDATE;
  IF i.id IS NULL OR asset.id IS NULL OR i.uploaded_by IS NULL OR i.state<>'ready' OR i.intended_matter_id IS NULL OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=i.org_id AND ia.intake_item_id=i.id) OR NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=i.intended_matter_id AND m.org_id=i.org_id AND m.status='active' AND m.deleted_at IS NULL AND m.record_state='active') OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships m LEFT JOIN public.organisations o ON o.id=m.org_id WHERE m.org_id=i.org_id AND m.user_id=i.uploaded_by AND m.state='active' AND (m.role IN ('admin','associate') OR o.owner_membership_id=m.id)) THEN RETURN QUERY SELECT 'not_auto_assignable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.document_versions existing WHERE existing.org_id=i.org_id AND existing.asset_id=asset.id AND existing.validation_state='valid' AND existing.state IN ('current','superseded')) THEN
    INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code) VALUES(i.org_id,i.uploaded_by,'auto_assign_intake',p_validation_event_id,i.id,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  INSERT INTO public.documents AS document_record (org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES(i.org_id,i.intended_matter_id,(SELECT declared_filename FROM public.upload_sessions WHERE id=i.upload_session_id AND org_id=i.org_id),'upload','active','metadata_only','placed',NULL,i.uploaded_by) RETURNING document_record.id INTO d;
  v:=public.document_materialization_insert_version(i.org_id,d,i.id,i.uploaded_by,NULL);
  UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions dv WHERE dv.id=v),effective_size_bytes=(SELECT source.byte_size FROM public.file_assets source JOIN public.document_versions dv ON dv.asset_id=source.id WHERE dv.id=v) WHERE document_record.id=d RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(i.org_id,i.id,d,v,i.uploaded_by);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(i.org_id,i.uploaded_by,'document.intake_assigned','document',d,'Assigned validated intake to its intended matter',jsonb_build_object('document_id',d::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(i.org_id,i.uploaded_by,'auto_assign_intake',p_validation_event_id,i.id,'ok',d,v,rev);
  PERFORM public.document_materialization_safe_event(i.org_id,d,'document.processing_requested.v1','document.processing.intended_assign.'||v::text,jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

REVOKE ALL ON FUNCTION public.document_materialization_insert_version(uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) TO service_role;
COMMENT ON FUNCTION public.document_materialization_insert_version(uuid,uuid,uuid,uuid,text) IS
  'Service-only version insert primitive. Serializes on organisation/SHA and rejects a valid current/superseded reference owned by another logical document; same-document audited history remains permitted.';
COMMENT ON FUNCTION public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid) IS
  'Authenticated attachment with organisation/SHA serialization and typed cross-document exact-PDF duplicate rejection.';
COMMENT ON FUNCTION public.replace_document_version(uuid,uuid,bigint,text,uuid,uuid) IS
  'Authenticated replacement with organisation/SHA serialization. Same-document history is retained; cross-document exact-PDF materialisation returns duplicate_reference.';
COMMENT ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) IS
  'Service-only intended-matter assignment with organisation/SHA serialization and typed cross-document exact-PDF duplicate rejection.';
COMMIT;
