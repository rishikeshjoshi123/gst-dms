-- Organisation-local exact-PDF duplicate resolution after the Trash foundation.
-- This migration deliberately adds no Trash read, restore, or purge authority.
BEGIN;

-- The lookup exposes an identifier only for a document or unassigned Intake the
-- caller may use in the ordinary active workspace.  Trash and restricted
-- matches remain intentionally opaque.
-- PostgreSQL cannot CREATE OR REPLACE a function while changing OUT columns.
-- The prior resolver has no dependent database objects (checked before this
-- migration was authored); callers use the stable function signature and the
-- explicit grant below is restored immediately.
DROP FUNCTION IF EXISTS public.get_intake_duplicate_resolution(uuid);
CREATE OR REPLACE FUNCTION public.get_intake_duplicate_resolution(p_intake_id uuid)
RETURNS TABLE(code text, document_id uuid, matter_id uuid, intake_id uuid)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  WITH actor AS (
    SELECT org_id
    FROM public.get_my_organisation_context()
    WHERE state = 'active'
      AND 'document.view' = ANY(capabilities)
      AND auth.uid() IS NOT NULL
    LIMIT 1
  ), duplicate_asset AS (
    SELECT i.org_id, receipt.duplicate_asset_id AS asset_id
    FROM actor
    JOIN public.intake_items AS i
      ON i.id = p_intake_id
     AND i.org_id = actor.org_id
     AND i.state = 'duplicate'
    JOIN public.document_upload_command_receipts AS receipt
      ON receipt.org_id = i.org_id
     AND receipt.upload_session_id = i.upload_session_id
     AND receipt.command = 'complete'
     AND receipt.code = 'duplicate'
    WHERE receipt.duplicate_asset_id IS NOT NULL
  ), active_document AS (
    SELECT d.id AS document_id, d.matter_id
    FROM duplicate_asset AS match
    JOIN public.document_versions AS version
      ON version.org_id = match.org_id
     AND version.asset_id = match.asset_id
     AND version.validation_state = 'valid'
     AND version.state IN ('current', 'superseded')
    JOIN public.documents AS d
      ON d.id = version.document_id
     AND d.org_id = match.org_id
    JOIN public.matters AS m
      ON m.id = d.matter_id
     AND m.org_id = d.org_id
    JOIN public.clients AS c
      ON c.id = m.client_id
     AND c.org_id = m.org_id
    WHERE d.record_state::text = 'active'
      AND d.deleted_at IS NULL
      AND m.record_state = 'active'
      AND m.deleted_at IS NULL
      AND c.record_state = 'active'
      AND c.deleted_at IS NULL
    ORDER BY (d.current_version_id = version.id) DESC, version.created_at DESC, d.created_at DESC
    LIMIT 1
  ), live_intake AS (
    SELECT candidate.id AS intake_id
    FROM duplicate_asset AS match
    JOIN public.intake_items AS subject
      ON subject.id = p_intake_id
     AND subject.org_id = match.org_id
    JOIN public.intake_items AS candidate
      ON candidate.org_id = match.org_id
     AND candidate.asset_id = match.asset_id
     AND candidate.id <> subject.id
    LEFT JOIN public.intake_item_assignments AS assignment
      ON assignment.org_id = candidate.org_id
     AND assignment.intake_item_id = candidate.id
    WHERE assignment.id IS NULL
      AND candidate.state NOT IN ('assigned', 'duplicate', 'failed', 'discarded', 'expired')
    ORDER BY candidate.created_at ASC
    LIMIT 1
  ), trash_document AS (
    SELECT 1
    FROM duplicate_asset AS match
    JOIN public.document_versions AS version
      ON version.org_id = match.org_id
     AND version.asset_id = match.asset_id
     AND version.validation_state = 'valid'
     AND version.state IN ('current', 'superseded')
    JOIN public.documents AS d
      ON d.id = version.document_id
     AND d.org_id = match.org_id
    LEFT JOIN public.matters AS m
      ON m.id = d.matter_id
     AND m.org_id = d.org_id
    LEFT JOIN public.clients AS c
      ON c.id = m.client_id
     AND c.org_id = m.org_id
    LEFT JOIN public.resource_trash_memberships AS membership
      ON membership.org_id = d.org_id
     AND membership.resource_type = 'document'
     AND membership.resource_id = d.id
     AND membership.state IN ('active', 'restoring', 'purging')
    WHERE d.record_state::text IN ('trashed', 'purging')
       OR d.deleted_at IS NOT NULL
       OR d.active_trash_membership_id IS NOT NULL
       OR m.record_state IN ('trashed', 'purging')
       OR m.deleted_at IS NOT NULL
       OR m.active_trash_membership_id IS NOT NULL
       OR c.record_state IN ('trashed', 'purging')
       OR c.deleted_at IS NOT NULL
       OR c.active_trash_membership_id IS NOT NULL
       OR membership.id IS NOT NULL
    LIMIT 1
  ), restricted_reference AS (
    SELECT 1
    FROM duplicate_asset AS match
    JOIN public.document_versions AS version
      ON version.org_id = match.org_id
     AND version.asset_id = match.asset_id
     AND version.validation_state = 'valid'
     AND version.state IN ('current', 'superseded')
    LIMIT 1
  )
  SELECT CASE
           WHEN active_document.document_id IS NOT NULL THEN 'ok'
           WHEN live_intake.intake_id IS NOT NULL THEN 'intake'
           WHEN EXISTS (SELECT 1 FROM trash_document) THEN 'in_trash'
           WHEN EXISTS (SELECT 1 FROM restricted_reference) THEN 'restricted'
           ELSE 'not_available'
         END,
         active_document.document_id,
         active_document.matter_id,
         live_intake.intake_id
  FROM (SELECT 1) AS result
  LEFT JOIN active_document ON true
  LEFT JOIN live_intake ON true;
$$;

-- Assignment uses the same organisation/hash lock as finalisation, then
-- re-reads durable valid version lineage.  A Trash reference is just as much
-- a duplicate as an active reference; do not materialise a new document.
CREATE OR REPLACE FUNCTION public.assign_intake_to_new_document(
  p_intake_id uuid,
  p_matter_id uuid,
  p_display_title text,
  p_expected_intake_uploader uuid,
  p_idempotency uuid
)
RETURNS TABLE(code text, document_id uuid, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  x record;
  i public.intake_items%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  d uuid;
  v uuid;
  rev bigint;
  prior public.document_command_receipts%ROWTYPE;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.intake.assign') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL OR p_display_title IS NULL
     OR char_length(p_display_title) NOT BETWEEN 1 AND 255 OR p_display_title ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::uuid, NULL::bigint;
    RETURN;
  END IF;

  -- Serialize same actor/key replays before reading the receipt. Without this
  -- fence, a second request can observe no receipt, wait behind the source
  -- lock, then incorrectly return intake_unavailable after the first commits.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text),
    pg_catalog.hashtext(x.actor_id::text || ':assign_intake:' || p_idempotency::text)
  );
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id = x.org_id AND actor_user_id = x.actor_id
    AND command_kind = 'assign_intake' AND idempotency_key = p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM p_intake_id THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text, NULL::uuid, NULL::uuid, NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code, prior.document_id, prior.document_version_id, prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO i FROM public.intake_items
  WHERE id = p_intake_id AND org_id = x.org_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid, NULL::bigint; RETURN; END IF;
  IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.uploaded_by IS NULL THEN
    RETURN QUERY SELECT 'uploader_mismatch'::text, NULL::uuid, NULL::uuid, NULL::bigint; RETURN;
  END IF;
  IF i.state <> 'ready' OR EXISTS (SELECT 1 FROM public.intake_item_assignments ia WHERE ia.org_id=x.org_id AND ia.intake_item_id=i.id) THEN
    RETURN QUERY SELECT 'intake_unavailable'::text, NULL::uuid, NULL::uuid, NULL::bigint; RETURN;
  END IF;
  SELECT * INTO asset FROM public.file_assets
  WHERE id = i.asset_id AND org_id = x.org_id FOR UPDATE;
  IF asset.id IS NULL OR asset.sha256 IS NULL OR asset.sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'intake_unavailable'::text, NULL::uuid, NULL::uuid, NULL::bigint; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text), pg_catalog.hashtext(asset.sha256)
  );
  -- The lock may have waited behind finalisation or another assignment. Re-read
  -- both the subject and all valid durable references under that fence.
  SELECT * INTO i FROM public.intake_items
  WHERE id = p_intake_id AND org_id = x.org_id FOR UPDATE;
  SELECT * INTO asset FROM public.file_assets
  WHERE id = i.asset_id AND org_id = x.org_id FOR UPDATE;
  IF i.state <> 'ready' OR asset.id IS NULL OR asset.sha256 IS NULL
     OR EXISTS (
       SELECT 1
       FROM public.document_versions AS existing
       WHERE existing.org_id = x.org_id
         AND existing.asset_id = asset.id
         AND existing.validation_state = 'valid'
         AND existing.state IN ('current', 'superseded')
     ) THEN
    INSERT INTO public.document_command_receipts(
      org_id, actor_user_id, command_kind, idempotency_key, subject_id, result_code
    ) VALUES (x.org_id, x.actor_id, 'assign_intake', p_idempotency, i.id, 'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text, NULL::uuid, NULL::uuid, NULL::bigint;
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.matters AS m
    JOIN public.clients AS c ON c.id=m.client_id AND c.org_id=m.org_id
    WHERE m.id=p_matter_id AND m.org_id=x.org_id AND m.status='active'
      AND m.deleted_at IS NULL AND m.record_state='active'
      AND c.deleted_at IS NULL AND c.record_state='active'
  ) THEN RETURN QUERY SELECT 'invalid_matter'::text, NULL::uuid, NULL::uuid, NULL::bigint; RETURN; END IF;

  INSERT INTO public.documents AS document_record
    (org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by)
  VALUES (x.org_id,p_matter_id,p_display_title,'upload','active','metadata_only','placed',NULL,x.actor_id)
  RETURNING document_record.id INTO d;
  v := public.document_materialization_insert_version(x.org_id,d,i.id,x.actor_id,NULL);
  UPDATE public.documents AS document_record
  SET current_version_id=v, content_availability='source_attached',
      effective_filename=(SELECT version.original_filename FROM public.document_versions AS version WHERE version.id=v),
      effective_size_bytes=(SELECT source.byte_size FROM public.file_assets AS source JOIN public.document_versions AS version ON version.asset_id=source.id WHERE version.id=v)
  WHERE document_record.id=d RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by)
    VALUES(x.org_id,i.id,d,v,x.actor_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata)
    VALUES(x.org_id,x.actor_id,'document.intake_assigned','document',d,'Assigned validated intake to a new document',jsonb_build_object('document_id',d::text,'version_id',v::text));
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision)
    VALUES(x.org_id,x.actor_id,'assign_intake',p_idempotency,i.id,'ok',d,v,rev);
  PERFORM public.document_materialization_safe_event(x.org_id,d,'document.processing_requested.v1','document.processing.assign.'||v::text,jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text));
  RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

REVOKE ALL ON FUNCTION public.get_intake_duplicate_resolution(uuid), public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_intake_duplicate_resolution(uuid), public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_intake_duplicate_resolution(uuid) IS
  'Authenticated, non-disclosing exact-PDF duplicate resolver. Active documents and live Intake may be identified; Trash and restricted matches never expose identifiers.';
COMMENT ON FUNCTION public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid) IS
  'Authenticated Intake assignment with organisation/hash serialization and a valid document-version duplicate fence.';
COMMIT;
