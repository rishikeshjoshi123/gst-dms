-- Root-scoped, atomic Trash restore authority.
--
-- Restoration is deliberately operation-scoped. Browser callers receive only
-- a bounded preflight projection and may mutate state only through the
-- authenticated SECURITY DEFINER command below. Permanent deletion remains
-- outside this migration.
BEGIN;

-- While a record is in Trash its active identifiers may legitimately be
-- reused. Keep the uniqueness rules aligned with the active-reader boundary so
-- restore can report a safe conflict instead of preventing the newer record.
ALTER TABLE public.matters DROP CONSTRAINT IF EXISTS matters_org_id_matter_code_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_matters_unique_active_org_code
  ON public.matters(org_id, matter_code)
  WHERE deleted_at IS NULL AND matter_code IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_unique_active_org_pan
  ON public.clients(org_id, pan)
  WHERE deleted_at IS NULL AND pan IS NOT NULL;

CREATE TABLE public.trash_restore_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (idempotency_key ~ '^[a-z][a-z0-9_.:-]{0,127}$'),
  result_code text NOT NULL CHECK (result_code IN (
    'restored', 'restore_blocked', 'purge_scheduled', 'not_available'
  )),
  blocker_code text,
  blocking_operation_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trash_restore_receipts_operation_org_fkey FOREIGN KEY (org_id, operation_id)
    REFERENCES public.trash_operations(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_restore_receipts_blocking_operation_org_fkey FOREIGN KEY (org_id, blocking_operation_id)
    REFERENCES public.trash_operations(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_restore_receipts_actor_key_unique UNIQUE (org_id, actor_user_id, idempotency_key),
  CONSTRAINT trash_restore_receipts_result_shape CHECK (
    (result_code = 'restore_blocked' AND blocker_code IS NOT NULL)
    OR (result_code <> 'restore_blocked' AND blocker_code IS NULL AND blocking_operation_id IS NULL)
  )
);
ALTER TABLE public.trash_restore_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_restore_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_restore_receipts FROM PUBLIC, anon, authenticated, service_role;

-- Trigger consumers record one bounded, content-free result per Restore event.
-- This is both the idempotency fence and durable proof that the event was
-- revalidated and handled before its delivery lease is acknowledged.
CREATE TABLE public.trash_restore_effect_receipts (
  event_id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  event_kind text NOT NULL CHECK (event_kind IN (
    'trash.operation_restored.v1',
    'trash.search_reindex_requested.v1',
    'trash.schedule_reevaluation_requested.v1'
  )),
  outcome_code text NOT NULL CHECK (outcome_code IN (
    'operation_reconciled', 'search_requeued', 'search_reconciled',
    'schedule_recalculated'
  )),
  affected_count integer NOT NULL CHECK (affected_count >= 0),
  handled_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trash_restore_effect_receipts_event_org_fkey
    FOREIGN KEY (org_id, event_id) REFERENCES public.outbox_events(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_restore_effect_receipts_operation_org_fkey
    FOREIGN KEY (org_id, operation_id) REFERENCES public.trash_operations(org_id, id) ON DELETE RESTRICT
);
ALTER TABLE public.trash_restore_effect_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_restore_effect_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_restore_effect_receipts FROM PUBLIC, anon, authenticated, service_role;

-- Return one safe blocker for the current locked/read snapshot. Identifiers of
-- conflicting records are intentionally not returned. The one exception is a
-- blocking parent operation, because the approved UI may link to that ancestor.
CREATE FUNCTION public.trash_restore_blocker(
  p_org_id uuid,
  p_operation_id uuid
)
RETURNS TABLE(blocker_code text, blocking_operation_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  operation public.trash_operations%ROWTYPE;
  root_matter public.matters%ROWTYPE;
  root_document public.documents%ROWTYPE;
  parent_operation uuid;
BEGIN
  SELECT * INTO operation FROM public.trash_operations
  WHERE org_id = p_org_id AND id = p_operation_id;
  IF operation.id IS NULL THEN
    RETURN QUERY SELECT 'invalid_operation'::text, NULL::uuid; RETURN;
  END IF;

  IF (SELECT count(*) FROM public.resource_trash_memberships membership
      WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
        AND membership.state='active')
     <> operation.included_client_count + operation.included_matter_count + operation.included_document_count
     OR (SELECT count(*) FROM public.resource_trash_memberships membership
         WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
           AND membership.state='active' AND membership.cause='direct'
           AND membership.parent_membership_id IS NULL
           AND membership.resource_type=operation.root_resource_type
           AND membership.resource_id=operation.root_resource_id) <> 1
     OR EXISTS (
       SELECT 1 FROM public.resource_trash_memberships membership
       WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
         AND membership.state<>'active'
     ) THEN
    RETURN QUERY SELECT 'membership_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    LEFT JOIN public.clients client ON membership.resource_type='client'
      AND client.org_id=membership.org_id AND client.id=membership.resource_id
      AND client.record_state='trashed' AND client.deleted_at IS NOT NULL
      AND client.active_trash_membership_id=membership.id
    LEFT JOIN public.matters matter ON membership.resource_type='matter'
      AND matter.org_id=membership.org_id AND matter.id=membership.resource_id
      AND matter.record_state='trashed' AND matter.deleted_at IS NOT NULL
      AND matter.active_trash_membership_id=membership.id
    LEFT JOIN public.documents document ON membership.resource_type='document'
      AND document.org_id=membership.org_id AND document.id=membership.resource_id
      AND document.record_state::text='trashed' AND document.deleted_at IS NOT NULL
      AND document.active_trash_membership_id=membership.id
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
      AND membership.state='active'
      AND ((membership.resource_type='client' AND client.id IS NULL)
        OR (membership.resource_type='matter' AND matter.id IS NULL)
        OR (membership.resource_type='document' AND document.id IS NULL))
  ) THEN
    RETURN QUERY SELECT 'resource_state_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships child
    LEFT JOIN public.resource_trash_memberships parent
      ON parent.org_id=child.org_id AND parent.id=child.parent_membership_id
      AND parent.operation_id=child.operation_id AND parent.state='active'
    LEFT JOIN public.matters matter
      ON child.resource_type='matter' AND matter.org_id=child.org_id AND matter.id=child.resource_id
    LEFT JOIN public.documents document
      ON child.resource_type='document' AND document.org_id=child.org_id AND document.id=child.resource_id
    WHERE child.org_id=p_org_id AND child.operation_id=p_operation_id
      AND child.state='active' AND child.cause='inherited'
      AND (parent.id IS NULL
        OR (child.resource_type='matter' AND (parent.resource_type<>'client' OR parent.resource_id<>matter.client_id))
        OR (child.resource_type='document' AND (parent.resource_type<>'matter' OR parent.resource_id<>document.matter_id)))
  ) THEN
    RETURN QUERY SELECT 'membership_lineage_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF operation.root_resource_type='matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE org_id=p_org_id AND id=operation.root_resource_id;
    IF root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'invalid_parent'::text, NULL::uuid; RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.clients client WHERE client.org_id=p_org_id
      AND client.id=root_matter.client_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.clients client
      JOIN public.resource_trash_memberships membership
        ON membership.org_id=client.org_id AND membership.id=client.active_trash_membership_id
      WHERE client.org_id=p_org_id AND client.id=root_matter.client_id AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
  ELSIF operation.root_resource_type='document' THEN
    SELECT * INTO root_document FROM public.documents WHERE org_id=p_org_id AND id=operation.root_resource_id;
    SELECT * INTO root_matter FROM public.matters WHERE org_id=p_org_id AND id=root_document.matter_id;
    IF root_document.id IS NULL OR root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'invalid_parent'::text, NULL::uuid; RETURN;
    END IF;
    IF root_matter.record_state<>'active' OR root_matter.deleted_at IS NOT NULL THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.resource_trash_memberships membership
      WHERE membership.org_id=p_org_id AND membership.id=root_matter.active_trash_membership_id
        AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.clients client WHERE client.org_id=p_org_id
      AND client.id=root_matter.client_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.clients client
      JOIN public.resource_trash_memberships membership
        ON membership.org_id=client.org_id AND membership.id=client.active_trash_membership_id
      WHERE client.org_id=p_org_id AND client.id=root_matter.client_id AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.clients restoring ON membership.resource_type='client'
      AND restoring.org_id=membership.org_id AND restoring.id=membership.resource_id
    JOIN public.clients active ON active.org_id=restoring.org_id AND active.id<>restoring.id
      AND active.record_state='active' AND active.deleted_at IS NULL
      AND ((restoring.gstin IS NOT NULL AND active.gstin=restoring.gstin)
        OR (restoring.pan IS NOT NULL AND active.pan=restoring.pan))
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'client_identifier_conflict'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.matters restoring ON membership.resource_type='matter'
      AND restoring.org_id=membership.org_id AND restoring.id=membership.resource_id
    JOIN public.matters active ON active.org_id=restoring.org_id AND active.id<>restoring.id
      AND active.record_state='active' AND active.deleted_at IS NULL
      AND ((restoring.matter_code IS NOT NULL AND active.matter_code=restoring.matter_code)
        OR (active.client_id=restoring.client_id AND active.financial_year=restoring.financial_year))
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'matter_identifier_conflict'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.document_versions restoring_version
      ON membership.resource_type='document' AND restoring_version.org_id=membership.org_id
      AND restoring_version.document_id=membership.resource_id
    JOIN public.file_assets restoring_asset
      ON restoring_asset.org_id=restoring_version.org_id AND restoring_asset.id=restoring_version.asset_id
      AND restoring_asset.sha256 IS NOT NULL
    JOIN public.file_assets active_asset
      ON active_asset.org_id=restoring_asset.org_id AND active_asset.sha256=restoring_asset.sha256
    JOIN public.document_versions active_version
      ON active_version.org_id=active_asset.org_id AND active_version.asset_id=active_asset.id
      AND active_version.document_id<>membership.resource_id
    JOIN public.documents active_document
      ON active_document.org_id=active_version.org_id AND active_document.id=active_version.document_id
      AND active_document.record_state::text='active' AND active_document.deleted_at IS NULL
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'document_content_conflict'::text, NULL::uuid; RETURN;
  END IF;

  RETURN;
END $$;

CREATE FUNCTION public.get_trash_restore_preflight(p_operation_id uuid)
RETURNS TABLE(
  code text,
  can_restore boolean,
  blocker_code text,
  blocking_operation_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  operation public.trash_operations%ROWTYPE;
  root_membership public.resource_trash_memberships%ROWTYPE;
  caller record;
  blocker record;
  allowed boolean := false;
BEGIN
  IF p_operation_id IS NULL OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN RETURN; END IF;
  SELECT * INTO root_membership FROM public.resource_trash_memberships membership
    WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
      AND membership.resource_type=operation.root_resource_type
      AND membership.resource_id=operation.root_resource_id
      AND membership.cause='direct' AND membership.parent_membership_id IS NULL
      AND membership.state='active' LIMIT 1;
  allowed := caller.is_owner OR caller.role='admin'
    OR (caller.role='associate' AND operation.root_resource_type='document'
      AND root_membership.id IS NOT NULL AND operation.actor_user_id=auth.uid());
  IF NOT allowed THEN
    RETURN QUERY SELECT 'not_allowed'::text,false,NULL::text,NULL::uuid; RETURN;
  END IF;
  IF root_membership.id IS NULL OR operation.state NOT IN ('trashed','restore_blocked') THEN
    RETURN QUERY SELECT CASE WHEN operation.state='purge_scheduled' THEN 'purge_scheduled' ELSE 'not_available' END,
      false,NULL::text,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO blocker FROM public.trash_restore_blocker(operation.org_id,operation.id) LIMIT 1;
  IF blocker.blocker_code IS NOT NULL THEN
    RETURN QUERY SELECT 'restore_blocked'::text,false,blocker.blocker_code,blocker.blocking_operation_id; RETURN;
  END IF;
  RETURN QUERY SELECT 'ready'::text,true,NULL::text,NULL::uuid;
END $$;

-- Extend the identifier-only durable outbox vocabulary. No downstream job is
-- started optimistically; these pending intents are the explicit safe minimum
-- until domain-specific re-index and schedule workers adopt them.
CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_envelope_is_safe(
  p_event_kind text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb
) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $$
  WITH contract(event_kind, aggregate_type, identifier_key, expected_keys) AS (
    VALUES
      ('document.upload_reserved.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','asset_id']::text[]),
      ('document.upload_validation_requested.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','asset_id']::text[]),
      ('document.upload_duplicate.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id']::text[]),
      ('document.upload_failed.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','error_code']::text[]),
      ('document.upload_expired.v1', 'document_upload', 'session_id', ARRAY['session_id']::text[]),
      ('document.intake_validated.v1', 'document', 'intake_id', ARRAY['intake_id','asset_id','result_code']::text[]),
      ('document.intake_validation_failed.v1', 'document', 'intake_id', ARRAY['intake_id','asset_id','result_code']::text[]),
      ('document.metadata_created.v1', 'document', 'document_id', ARRAY['document_id','matter_id']::text[]),
      ('document.processing_requested.v1', 'document', 'document_id', ARRAY['document_id','version_id','intake_id']::text[]),
      ('document.reprocess_requested.v1', 'document', 'document_id', ARRAY['document_id','version_id','scope']::text[]),
      ('intake.assigned.v1', 'document', 'intake_id', ARRAY['intake_id','document_id','document_version_id']::text[]),
      ('intake.discarded.v1', 'document', 'intake_id', ARRAY['intake_id','result_code']::text[]),
      ('trash.operation_created.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.operation_restored.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.search_reindex_requested.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.schedule_reevaluation_requested.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[])
  )
  SELECT coalesce((SELECT p_event_kind IS NOT NULL AND p_aggregate_type=c.aggregate_type
    AND p_aggregate_id IS NOT NULL AND jsonb_typeof(p_payload)='object'
    AND p_aggregate_id::text=p_payload->>c.identifier_key
    AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE NOT key=ANY(c.expected_keys))
    AND NOT EXISTS (SELECT 1 FROM unnest(c.expected_keys) key WHERE NOT p_payload?key
      OR jsonb_typeof(p_payload->key)<>'string' OR char_length(p_payload->>key) NOT BETWEEN 1 AND 128)
    AND NOT EXISTS (SELECT 1 FROM unnest(ARRAY['session_id','intake_id','asset_id','document_id','matter_id','version_id','document_version_id','operation_id','root_resource_id']::text[]) key
      WHERE p_payload?key AND p_payload->>key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    AND (NOT p_payload?'scope' OR p_payload->>'scope' IN ('extract','ocr','relationships','search_index','full'))
    AND (NOT p_payload?'root_resource_type' OR p_payload->>'root_resource_type' IN ('client','matter','document'))
    AND (NOT p_payload?'error_code' OR p_payload->>'error_code' IN ('upload_failed','invalid_pdf','malware_suspect','storage_missing','validation_failed','upload_rejected'))
    AND (NOT p_payload?'result_code' OR p_payload->>'result_code' IN ('ok','already_ready','not_available','invalid_pdf','encrypted_pdf','malware_suspect','storage_missing','validation_failed','discarded'))
    FROM contract c WHERE c.event_kind=p_event_kind),false)
$$;

CREATE FUNCTION public.restore_trash_operation(p_operation_id uuid, p_idempotency_key text)
RETURNS TABLE(
  code text,
  operation_id uuid,
  blocker_code text,
  blocking_operation_id uuid,
  root_resource_type public.trash_resource_type,
  root_resource_id uuid,
  root_client_id uuid,
  root_matter_id uuid,
  root_document_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  operation public.trash_operations%ROWTYPE;
  root_membership public.resource_trash_memberships%ROWTYPE;
  caller record;
  prior public.trash_restore_receipts%ROWTYPE;
  blocker record;
  v_result_code text;
  result_blocker text;
  result_blocking_operation uuid;
  content_sha record;
BEGIN
  IF p_operation_id IS NULL OR p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$' OR auth.uid() IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('hierarchical-resource-trash'));
  SELECT locked_operation.* INTO operation FROM public.trash_operations locked_operation
    WHERE locked_operation.org_id=operation.org_id AND locked_operation.id=p_operation_id FOR UPDATE;
  SELECT * INTO root_membership FROM public.resource_trash_memberships membership
    WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
      AND membership.resource_type=operation.root_resource_type AND membership.resource_id=operation.root_resource_id
      AND membership.cause='direct' AND membership.parent_membership_id IS NULL AND membership.state='active'
    LIMIT 1 FOR UPDATE;
  -- Replay authority is derived from the immutable operation subject. The
  -- live direct-root membership is required below for a first execution, but
  -- is intentionally absent after a successful Restore.
  IF NOT (caller.is_owner OR caller.role='admin'
    OR (caller.role='associate' AND operation.root_resource_type='document'
      AND operation.actor_user_id=auth.uid())) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),
    pg_catalog.hashtext(auth.uid()::text || ':restore:' || p_idempotency_key));
  SELECT * INTO prior FROM public.trash_restore_receipts receipt
    WHERE receipt.org_id=operation.org_id AND receipt.actor_user_id=auth.uid()
      AND receipt.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.operation_id<>operation.id THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::text,NULL::uuid,
        NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
    ELSE
      RETURN QUERY SELECT prior.result_code,operation.id,prior.blocker_code,prior.blocking_operation_id,
        operation.root_resource_type,operation.root_resource_id,operation.root_client_id,operation.root_matter_id,operation.root_document_id;
    END IF;
    RETURN;
  END IF;

  IF operation.state='purge_scheduled' THEN
    v_result_code := 'purge_scheduled';
  ELSIF operation.state NOT IN ('trashed','restore_blocked') OR root_membership.id IS NULL THEN
    v_result_code := 'not_available';
  ELSE
    -- Lock and re-read every member and resource in a stable type/ID order.
    PERFORM 1 FROM public.resource_trash_memberships membership
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
      ORDER BY membership.resource_type,membership.resource_id FOR UPDATE;
    PERFORM 1 FROM public.clients client JOIN public.resource_trash_memberships membership
      ON membership.org_id=client.org_id AND membership.resource_type='client' AND membership.resource_id=client.id
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id ORDER BY client.id FOR UPDATE OF client;
    PERFORM 1 FROM public.matters matter JOIN public.resource_trash_memberships membership
      ON membership.org_id=matter.org_id AND membership.resource_type='matter' AND membership.resource_id=matter.id
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id ORDER BY matter.id FOR UPDATE OF matter;
    PERFORM 1 FROM public.documents document JOIN public.resource_trash_memberships membership
      ON membership.org_id=document.org_id AND membership.resource_type='document' AND membership.resource_id=document.id
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id ORDER BY document.id FOR UPDATE OF document;

    -- Version writers serialize every logical PDF decision on this exact
    -- organisation/SHA fence. Acquire all hashes in lexical order, then let
    -- trash_restore_blocker re-read active references while those writer
    -- decisions are fenced. This prevents a writer from materialising a
    -- cross-document reference between Restore preflight and activation.
    FOR content_sha IN
      SELECT DISTINCT asset.sha256
      FROM public.resource_trash_memberships membership
      JOIN public.document_versions version
        ON membership.resource_type='document' AND version.org_id=membership.org_id
        AND version.document_id=membership.resource_id
        AND version.validation_state='valid' AND version.state IN ('current','superseded')
      JOIN public.file_assets asset
        ON asset.org_id=version.org_id AND asset.id=version.asset_id
        AND asset.sha256 ~ '^[0-9a-f]{64}$'
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
        AND membership.state='active'
      ORDER BY asset.sha256
    LOOP
      PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext(operation.org_id::text),
        pg_catalog.hashtext(content_sha.sha256)
      );
    END LOOP;

    SELECT * INTO blocker FROM public.trash_restore_blocker(operation.org_id,operation.id) LIMIT 1;
    IF blocker.blocker_code IS NOT NULL THEN
      v_result_code := 'restore_blocked'; result_blocker := blocker.blocker_code;
      result_blocking_operation := blocker.blocking_operation_id;
      UPDATE public.trash_operations target SET state='restore_blocked',restore_blocked_at=coalesce(target.restore_blocked_at,now()),
        restore_started_at=NULL,last_error_code=result_blocker,updated_at=now()
      WHERE target.org_id=operation.org_id AND target.id=operation.id;
    ELSE
      BEGIN
        UPDATE public.trash_operations target SET state='restoring',restore_started_at=now(),last_error_code=NULL,updated_at=now()
          WHERE target.org_id=operation.org_id AND target.id=operation.id;
        UPDATE public.resource_trash_memberships target SET state='restoring',updated_at=now()
          WHERE target.org_id=operation.org_id AND target.operation_id=operation.id AND target.state='active';
        UPDATE public.clients client SET record_state='active',active_trash_membership_id=NULL,deleted_at=NULL
          FROM public.resource_trash_memberships membership
          WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
            AND membership.resource_type='client' AND membership.resource_id=client.id AND client.org_id=membership.org_id;
        UPDATE public.matters matter SET record_state='active',active_trash_membership_id=NULL,deleted_at=NULL
          FROM public.resource_trash_memberships membership
          WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
            AND membership.resource_type='matter' AND membership.resource_id=matter.id AND matter.org_id=membership.org_id;
        UPDATE public.documents document SET record_state='active',active_trash_membership_id=NULL,deleted_at=NULL,
          trashed_at=NULL,trashed_by=NULL,trashed_reason=NULL,restored_at=now()
          FROM public.resource_trash_memberships membership
          WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
            AND membership.resource_type='document' AND membership.resource_id=document.id AND document.org_id=membership.org_id;
        UPDATE public.resource_trash_memberships target SET state='restored',restored_at=now(),updated_at=now()
          WHERE target.org_id=operation.org_id AND target.operation_id=operation.id AND target.state='restoring';
        UPDATE public.trash_operations target SET state='restored',restored_at=now(),last_error_code=NULL,updated_at=now()
          WHERE target.org_id=operation.org_id AND target.id=operation.id;
        v_result_code := 'restored';
      EXCEPTION WHEN unique_violation THEN
        v_result_code := 'restore_blocked'; result_blocker := 'uniqueness_conflict';
        UPDATE public.trash_operations target SET state='restore_blocked',restore_blocked_at=coalesce(target.restore_blocked_at,now()),
          restore_started_at=NULL,last_error_code=result_blocker,updated_at=now()
        WHERE target.org_id=operation.org_id AND target.id=operation.id;
      END;
    END IF;
  END IF;

  INSERT INTO public.trash_restore_receipts(org_id,operation_id,actor_user_id,idempotency_key,result_code,blocker_code,blocking_operation_id)
  VALUES(operation.org_id,operation.id,auth.uid(),p_idempotency_key,v_result_code,result_blocker,result_blocking_operation);

  IF v_result_code='restored' THEN
    INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata,is_reversible)
    VALUES(operation.org_id,auth.uid(),'resource_restored',operation.root_resource_type::text::public.entity_type,
      operation.root_resource_id,'Restored resource from Trash',
      jsonb_build_object('operation_id',operation.id::text,'resource_type',operation.root_resource_type::text),false);
    INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
    SELECT operation.org_id,'trash_operation',operation.id,event_kind,
      jsonb_build_object('operation_id',operation.id::text,'root_resource_id',operation.root_resource_id::text,'root_resource_type',operation.root_resource_type::text),
      'trash.restore.'||operation.id::text||'.'||suffix
    FROM (VALUES
      ('trash.operation_restored.v1','restored'),
      ('trash.search_reindex_requested.v1','search'),
      ('trash.schedule_reevaluation_requested.v1','schedule')
    ) event(event_kind,suffix);
  END IF;

  RETURN QUERY SELECT v_result_code,operation.id,result_blocker,result_blocking_operation,
    operation.root_resource_type,operation.root_resource_id,operation.root_client_id,operation.root_matter_id,operation.root_document_id;
END $$;

-- Handle one leased Restore effect synchronously. The function never accepts
-- caller-provided resource locators: it binds the identifier-only envelope to
-- the immutable operation, its restored memberships, and current lifecycle
-- state. Search work is delegated only to the existing proven-idempotent
-- search_index worker. Schedule recalculation marks elapsed reminder windows
-- as observed so restoration cannot create a burst of missed alerts; future
-- windows stay eligible for the ordinary deadline scheduler.
CREATE FUNCTION public.handle_trash_restore_effect(
  p_event_id uuid,
  p_expected_org_id uuid,
  p_delivery_lease_token uuid,
  p_expected_event_kind text
)
RETURNS TABLE(code text, outcome_code text, affected_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  event_row public.outbox_events%ROWTYPE;
  operation public.trash_operations%ROWTYPE;
  prior public.trash_restore_effect_receipts%ROWTYPE;
  restored_document record;
  child_event_id uuid;
  child_event_key text;
  child_run_key text;
  effect_outcome text;
  affected integer := 0;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL OR p_delivery_lease_token IS NULL
     OR p_expected_event_kind NOT IN (
       'trash.operation_restored.v1',
       'trash.search_reindex_requested.v1',
       'trash.schedule_reevaluation_requested.v1'
     ) THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::text,0; RETURN;
  END IF;

  SELECT outbox.* INTO event_row FROM public.outbox_events outbox
  WHERE outbox.id=p_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.org_id IS DISTINCT FROM p_expected_org_id
     OR event_row.event_kind IS DISTINCT FROM p_expected_event_kind
     OR event_row.aggregate_type<>'trash_operation'
     OR event_row.aggregate_id::text IS DISTINCT FROM event_row.payload->>'operation_id'
     OR event_row.delivery_state<>'leased'
     OR event_row.lease_token IS DISTINCT FROM p_delivery_lease_token
     OR event_row.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'invalid_event'::text,NULL::text,0; RETURN;
  END IF;

  SELECT receipt.* INTO prior FROM public.trash_restore_effect_receipts receipt
  WHERE receipt.event_id=event_row.id;
  IF prior.event_id IS NOT NULL THEN
    RETURN QUERY SELECT 'already_handled'::text,prior.outcome_code,prior.affected_count; RETURN;
  END IF;

  SELECT trash_operation.* INTO operation FROM public.trash_operations trash_operation
  WHERE trash_operation.org_id=event_row.org_id AND trash_operation.id=event_row.aggregate_id
  FOR KEY SHARE;
  IF operation.id IS NULL OR operation.state<>'restored'
     OR operation.root_resource_id::text IS DISTINCT FROM event_row.payload->>'root_resource_id'
     OR operation.root_resource_type::text IS DISTINCT FROM event_row.payload->>'root_resource_type'
     OR EXISTS (
       SELECT 1 FROM public.resource_trash_memberships membership
       WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
         AND membership.state<>'restored'
     ) THEN
    RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
  END IF;

  IF event_row.event_kind='trash.operation_restored.v1' THEN
    SELECT count(*)::integer INTO affected
    FROM public.resource_trash_memberships membership
    WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
      AND membership.state='restored';
    effect_outcome:='operation_reconciled';
  ELSIF event_row.event_kind='trash.search_reindex_requested.v1' THEN
    FOR restored_document IN
      SELECT document.id,document.current_version_id
      FROM public.resource_trash_memberships membership
      JOIN public.documents document
        ON membership.resource_type='document' AND document.org_id=membership.org_id
        AND document.id=membership.resource_id
      JOIN public.document_versions version
        ON version.org_id=document.org_id AND version.id=document.current_version_id
        AND version.document_id=document.id AND version.state='current'
        AND version.validation_state='valid'
      JOIN public.file_assets asset
        ON asset.org_id=version.org_id AND asset.id=version.asset_id
        AND asset.availability='available' AND asset.storage_deleted_at IS NULL
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
        AND membership.state='restored' AND document.record_state='active'
        AND document.deleted_at IS NULL
      ORDER BY document.id
    LOOP
      child_event_key:='trash.restore.search.'||operation.id::text||'.'||restored_document.id::text;
      child_run_key:='trash.restore.search.run.'||operation.id::text||'.'||restored_document.id::text;
      INSERT INTO public.outbox_events(
        org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key
      ) VALUES (
        operation.org_id,'document',restored_document.id,'document.reprocess_requested.v1',
        jsonb_build_object(
          'document_id',restored_document.id::text,
          'version_id',restored_document.current_version_id::text,
          'scope','search_index'
        ),child_event_key
      )
      ON CONFLICT (org_id,idempotency_key) DO UPDATE
        SET idempotency_key=excluded.idempotency_key
      RETURNING id INTO child_event_id;
      INSERT INTO public.document_processing_runs(
        org_id,document_id,document_version_id,scope,stage,state,idempotency_key,outbox_event_id
      ) VALUES (
        operation.org_id,restored_document.id,restored_document.current_version_id,
        'search_index','queued','queued',child_run_key,child_event_id
      ) ON CONFLICT (org_id,idempotency_key) DO NOTHING;
      affected:=affected+1;
    END LOOP;
    effect_outcome:=CASE WHEN affected>0 THEN 'search_requeued' ELSE 'search_reconciled' END;
  ELSE
    WITH candidates AS (
      SELECT deadline.id
      FROM public.deadlines deadline
      JOIN public.matters matter
        ON matter.id=deadline.matter_id AND matter.org_id=operation.org_id
        AND matter.record_state='active' AND matter.deleted_at IS NULL
      LEFT JOIN public.documents document
        ON document.id=deadline.document_id AND document.org_id=operation.org_id
      WHERE NOT deadline.is_resolved
        AND (
          (deadline.document_id IS NULL AND EXISTS (
            SELECT 1 FROM public.resource_trash_memberships membership
            WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
              AND membership.state='restored' AND membership.resource_type='matter'
              AND membership.resource_id=deadline.matter_id
          ))
          OR (deadline.document_id IS NOT NULL AND document.record_state='active'
            AND document.deleted_at IS NULL AND EXISTS (
              SELECT 1 FROM public.resource_trash_memberships membership
              WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
                AND membership.state='restored' AND membership.resource_type='document'
                AND membership.resource_id=deadline.document_id
            ))
        )
      ORDER BY deadline.id FOR UPDATE OF deadline
    )
    UPDATE public.deadlines deadline SET
      reminder_sent_30d=deadline.reminder_sent_30d OR deadline.due_date<=current_date,
      reminder_sent_7d=deadline.reminder_sent_7d OR deadline.due_date<=current_date
    FROM candidates WHERE deadline.id=candidates.id;
    GET DIAGNOSTICS affected = ROW_COUNT;
    effect_outcome:='schedule_recalculated';
  END IF;

  INSERT INTO public.trash_restore_effect_receipts(
    event_id,org_id,operation_id,event_kind,outcome_code,affected_count
  ) VALUES (
    event_row.id,event_row.org_id,operation.id,event_row.event_kind,effect_outcome,affected
  );
  RETURN QUERY SELECT 'handled'::text,effect_outcome,affected;
END $$;

-- A queue acceptance is not completion for dependent Restore work. Preserve
-- the shared delivery authority while adding a database-level fence that
-- refuses to acknowledge these three event kinds until their idempotent
-- consumer receipt exists.
CREATE OR REPLACE FUNCTION public.ack_document_outbox_event(
  p_event_id uuid,
  p_lease_token uuid,
  p_trigger_run_id text
) RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE event_row public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL OR p_trigger_run_id IS NULL
     OR p_trigger_run_id !~ '^[A-Za-z0-9._:-]{1,200}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT outbox.* INTO event_row FROM public.outbox_events outbox
  WHERE outbox.id=p_event_id FOR UPDATE;
  IF event_row.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text; RETURN;
  END IF;
  IF event_row.delivery_state='delivered' THEN
    RETURN QUERY SELECT CASE
      WHEN event_row.trigger_run_id=p_trigger_run_id THEN 'already_accepted'::text
      ELSE 'delivery_already_complete'::text END;
    RETURN;
  END IF;
  IF event_row.delivery_state<>'leased'
     OR event_row.lease_token IS DISTINCT FROM p_lease_token
     OR event_row.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text; RETURN;
  END IF;
  IF event_row.event_kind IN (
       'trash.operation_restored.v1',
       'trash.search_reindex_requested.v1',
       'trash.schedule_reevaluation_requested.v1'
     ) AND NOT EXISTS (
       SELECT 1 FROM public.trash_restore_effect_receipts receipt
       WHERE receipt.org_id=event_row.org_id AND receipt.event_id=event_row.id
         AND receipt.event_kind=event_row.event_kind
     ) THEN
    RETURN QUERY SELECT 'effect_not_handled'::text; RETURN;
  END IF;
  UPDATE public.outbox_events outbox SET
    delivery_state='delivered',lease_token=NULL,lease_expires_at=NULL,
    delivered_at=now(),trigger_run_id=p_trigger_run_id,last_error_code=NULL,
    updated_at=now()
  WHERE outbox.id=event_row.id;
  INSERT INTO public.outbox_dispatch_attempts(
    event_id,org_id,attempt_number,lease_fingerprint,outcome,trigger_run_id
  ) VALUES (
    event_row.id,event_row.org_id,event_row.attempt_count,
    encode(extensions.digest(p_lease_token::text,'sha256'),'hex'),
    'accepted',p_trigger_run_id
  );
  RETURN QUERY SELECT 'ok'::text;
END $$;

REVOKE ALL ON FUNCTION public.trash_restore_blocker(uuid,uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_trash_restore_preflight(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.restore_trash_operation(uuid,text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.handle_trash_restore_effect(uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_trash_restore_preflight(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_trash_operation(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_trash_restore_effect(uuid,uuid,uuid,text) TO service_role;

COMMENT ON TABLE public.trash_restore_receipts IS
  'Service-private actor/key receipts for root-operation Restore replay. Contains identifiers and safe result codes only.';
COMMENT ON FUNCTION public.get_trash_restore_preflight(uuid) IS
  'Authenticated, tenant-scoped Restore authority and blocker preflight for one exact root Trash operation.';
COMMENT ON FUNCTION public.restore_trash_operation(uuid,text) IS
  'Authenticated root-only Restore command. Revalidates authority, lineage, parents, uniqueness, and operation membership under locks; emits durable identifier-only intents atomically.';
COMMENT ON TABLE public.trash_restore_effect_receipts IS
  'Private idempotent results for leased Restore event consumers; identifiers, safe outcome, and bounded counts only.';
COMMENT ON FUNCTION public.handle_trash_restore_effect(uuid,uuid,uuid,text) IS
  'Service-only leased Restore consumer. Revalidates tenant, operation, lifecycle, and delivery fence; queues bounded search indexing and recalculates future deadline reminder eligibility.';

COMMIT;
