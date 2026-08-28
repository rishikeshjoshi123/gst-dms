-- Explicit, tenant-authorised reprocess commands. This migration introduces
-- durable intent only; provider execution remains behind a later scoped-worker
-- contract and must not fall back to the legacy generic pipeline.
BEGIN;

-- Reprocessing is a consequential document mutation. Keep its capability in
-- the one versioned capability matrix rather than trusting a browser control.
CREATE OR REPLACE FUNCTION public.organisation_member_capabilities(
  p_role public.org_member_role,
  p_is_owner boolean,
  p_state public.organisation_membership_state
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_state <> 'active' THEN ARRAY[]::text[]
    WHEN p_is_owner THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','team.invite.admin','team.role.manage_admin',
      'team.membership.manage_admin','team.ownership.transfer','trash.purge',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess'
    ]::text[]
    WHEN p_role='admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','document.view',
      'document.intake.create','document.record.create','document.intake.assign',
      'document.intake.discard','document.version.attach','document.version.replace',
      'document.reprocess'
    ]::text[]
    WHEN p_role='associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess'
    ]::text[]
    ELSE ARRAY['team.view','document.view']::text[] END
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT m.id,m.org_id,m.role,(o.owner_membership_id=m.id),m.state,5,
    public.organisation_member_capabilities(m.role,o.owner_membership_id=m.id,m.state),m.revision
  FROM public.organisation_memberships AS m
  JOIN public.organisations AS o ON o.id=m.org_id
  WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')
$$;

ALTER TABLE public.document_command_receipts
  DROP CONSTRAINT document_command_receipts_command_kind_check;
ALTER TABLE public.document_command_receipts
  ADD CONSTRAINT document_command_receipts_command_kind_check
  CHECK (command_kind IN (
    'validate_asset','create_metadata','assign_intake','auto_assign_intake',
    'attach_intake','replace_version','discard_intake','reprocess'
  ));

-- Extend the immutable outbox contract before the command writer exists. The
-- envelope contains only routing identity and one allow-listed scope.
CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_envelope_is_safe(
  p_event_kind text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb
) RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  WITH contract(event_kind, aggregate_type, identifier_key, expected_keys) AS (
    VALUES
      ('document.upload_reserved.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_validation_requested.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'asset_id']::text[]),
      ('document.upload_duplicate.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id']::text[]),
      ('document.upload_failed.v1', 'document_upload', 'session_id', ARRAY['session_id', 'intake_id', 'error_code']::text[]),
      ('document.upload_expired.v1', 'document_upload', 'session_id', ARRAY['session_id']::text[]),
      ('document.intake_validated.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.intake_validation_failed.v1', 'document', 'intake_id', ARRAY['intake_id', 'asset_id', 'result_code']::text[]),
      ('document.metadata_created.v1', 'document', 'document_id', ARRAY['document_id', 'matter_id']::text[]),
      ('document.processing_requested.v1', 'document', 'document_id', ARRAY['document_id', 'version_id', 'intake_id']::text[]),
      ('document.reprocess_requested.v1', 'document', 'document_id', ARRAY['document_id', 'version_id', 'scope']::text[]),
      ('intake.assigned.v1', 'document', 'intake_id', ARRAY['intake_id', 'document_id', 'document_version_id']::text[]),
      ('intake.discarded.v1', 'document', 'intake_id', ARRAY['intake_id', 'result_code']::text[])
  )
  SELECT COALESCE((
    SELECT p_event_kind IS NOT NULL
      AND p_aggregate_type = c.aggregate_type
      AND p_aggregate_id IS NOT NULL
      AND jsonb_typeof(p_payload) = 'object'
      AND p_aggregate_id::text = p_payload ->> c.identifier_key
      AND NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_payload) AS payload_key
        WHERE NOT payload_key = ANY(c.expected_keys)
      )
      AND NOT EXISTS (
        SELECT 1 FROM unnest(c.expected_keys) AS expected_key
        WHERE NOT p_payload ? expected_key
          OR jsonb_typeof(p_payload -> expected_key) <> 'string'
          OR char_length(p_payload ->> expected_key) NOT BETWEEN 1 AND 128
      )
      AND NOT EXISTS (
        SELECT 1 FROM unnest(ARRAY['session_id', 'intake_id', 'asset_id', 'document_id', 'matter_id', 'version_id', 'document_version_id']::text[]) AS identifier_key
        WHERE p_payload ? identifier_key
          AND p_payload ->> identifier_key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      )
      AND (NOT p_payload ? 'scope' OR p_payload ->> 'scope' IN ('extract','ocr','relationships','search_index','full'))
      AND (NOT p_payload ? 'error_code' OR p_payload ->> 'error_code' IN ('upload_failed', 'invalid_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'upload_rejected'))
      AND (NOT p_payload ? 'result_code' OR p_payload ->> 'result_code' IN ('ok', 'already_ready', 'not_available', 'invalid_pdf', 'encrypted_pdf', 'malware_suspect', 'storage_missing', 'validation_failed', 'discarded'))
    FROM contract AS c
    WHERE c.event_kind = p_event_kind
  ), false)
$$;

-- One command creates the run, receipt, and safe outbox envelope in a single
-- transaction. A caller supplies exactly one enum scope and a capability
-- projection version; neither a document version nor a Trigger task is caller
-- selectable.
CREATE OR REPLACE FUNCTION public.request_document_reprocess(
  p_document_id uuid,
  p_scope public.document_processing_scope,
  p_idempotency uuid,
  p_capability_version integer
)
RETURNS TABLE(
  code text,
  document_id uuid,
  document_version_id uuid,
  processing_run_id uuid,
  outbox_event_id uuid,
  scope public.document_processing_scope
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  doc public.documents%ROWTYPE;
  ver public.document_versions%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  actor record;
  prior public.document_command_receipts%ROWTYPE;
  prior_event public.outbox_events%ROWTYPE;
  actor_id uuid;
  run_id uuid;
  event_id uuid;
  command_key text;
  run_key text;
  run_stage public.document_processing_stage;
BEGIN
  IF p_document_id IS NULL OR p_scope IS NULL OR p_idempotency IS NULL
     OR p_capability_version IS NULL
     OR p_scope NOT IN ('extract','ocr','relationships','search_index','full') THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;

  SELECT d.* INTO doc FROM public.documents AS d WHERE d.id=p_document_id FOR UPDATE;
  IF doc.id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;

  SELECT * INTO actor FROM public.get_my_organisation_context() AS context
  WHERE context.org_id=doc.org_id AND context.state='active' AND auth.uid() IS NOT NULL
  LIMIT 1;
  IF actor.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;
  actor_id:=auth.uid();
  IF actor.capability_version IS DISTINCT FROM p_capability_version THEN
    RETURN QUERY SELECT 'capability_version_mismatch'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;
  IF NOT ('document.reprocess'=ANY(actor.capabilities)) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;

  -- Serialize one actor's retries for one reprocess key before inspecting the
  -- receipt. This prevents concurrent first attempts from falling through to
  -- a unique-constraint exception; the second caller observes the committed
  -- receipt and deterministically receives an idempotent result instead.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(doc.org_id::text),
    pg_catalog.hashtext(actor_id::text||':reprocess:'||p_idempotency::text)
  );
  command_key:='document.reprocess.'||actor_id::text||'.'||p_idempotency::text;
  run_key:='reprocess.'||actor_id::text||'.'||p_idempotency::text;
  SELECT * INTO prior FROM public.document_command_receipts AS receipt
  WHERE receipt.org_id=doc.org_id AND receipt.actor_user_id=actor_id
    AND receipt.command_kind='reprocess' AND receipt.idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    SELECT * INTO prior_event FROM public.outbox_events AS event
    WHERE event.org_id=doc.org_id AND event.idempotency_key=command_key;
    SELECT id INTO run_id FROM public.document_processing_runs AS run
    WHERE run.org_id=doc.org_id AND run.idempotency_key=run_key;
    IF prior.subject_id IS DISTINCT FROM p_document_id
       OR prior_event.id IS NULL
       OR prior_event.payload->>'scope' IS DISTINCT FROM p_scope::text THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,prior.document_id,prior.document_version_id,run_id,prior_event.id,NULL::public.document_processing_scope;
    ELSE
      RETURN QUERY SELECT 'already_requested'::text,prior.document_id,prior.document_version_id,run_id,prior_event.id,p_scope;
    END IF;
    RETURN;
  END IF;

  SELECT dv.* INTO ver FROM public.document_versions AS dv
  WHERE dv.id=doc.current_version_id AND dv.document_id=doc.id AND dv.org_id=doc.org_id
  FOR UPDATE;
  SELECT fa.* INTO asset FROM public.file_assets AS fa
  WHERE fa.id=ver.asset_id AND fa.org_id=doc.org_id FOR UPDATE;
  IF doc.record_state<>'active' OR doc.deleted_at IS NOT NULL OR ver.id IS NULL
     OR ver.state<>'current' OR ver.validation_state<>'valid' OR asset.id IS NULL
     OR asset.availability<>'available' OR asset.storage_deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'not_available'::text,doc.id,NULL::uuid,NULL::uuid,NULL::uuid,NULL::public.document_processing_scope;
    RETURN;
  END IF;

  run_stage:=CASE
    WHEN p_scope IN ('extract','ocr','full') THEN 'extracting'::public.document_processing_stage
    WHEN p_scope='relationships' THEN 'matching'::public.document_processing_stage
    ELSE 'queued'::public.document_processing_stage
  END;
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(
    doc.org_id,'document',doc.id,'document.reprocess_requested.v1',
    jsonb_build_object('document_id',doc.id::text,'version_id',ver.id::text,'scope',p_scope::text),
    command_key
  )
  RETURNING id INTO event_id;
  INSERT INTO public.document_processing_runs(
    org_id,document_id,document_version_id,scope,stage,state,idempotency_key,outbox_event_id
  ) VALUES (
    doc.org_id,doc.id,ver.id,p_scope,run_stage,'queued',run_key,event_id
  )
  RETURNING id INTO run_id;
  INSERT INTO public.document_command_receipts(
    org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,
    document_id,document_version_id
  ) VALUES (
    doc.org_id,actor_id,'reprocess',p_idempotency,doc.id,'queued',doc.id,ver.id
  );
  RETURN QUERY SELECT 'queued'::text,doc.id,ver.id,run_id,event_id,p_scope;
END $$;

-- Existing generic processing has unfenced legacy effects. The only scope
-- approved for automatic replay is search indexing; all other scoped runs
-- become durable recovery work if a worker lease expires or reports failure.
ALTER TABLE public.document_processing_recovery_cases
  DROP CONSTRAINT document_processing_recovery_cases_recovery_reason_check;
ALTER TABLE public.document_processing_recovery_cases
  ADD CONSTRAINT document_processing_recovery_cases_recovery_reason_check
  CHECK (recovery_reason IN ('legacy_processing_replay_unsafe','scoped_reprocess_replay_unsafe'));

CREATE OR REPLACE FUNCTION public.reconcile_document_processing_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(validation_requeued integer, processing_requeued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE validation_count integer:=0; processing_count integer:=0;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'invalid batch size';
  END IF;
  WITH candidates AS (
    SELECT sar.id,sar.outbox_event_id FROM public.source_analysis_runs AS sar
    WHERE sar.outbox_event_id IS NOT NULL AND sar.state='running' AND sar.lease_expires_at<=now()
    ORDER BY coalesce(sar.lease_expires_at,sar.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.source_analysis_runs AS sar
    SET state='queued',started_at=NULL,failed_at=NULL,safe_error_code='work_requeued',
        lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE sar.id=candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,
        lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now()
    FROM reset_runs AS run WHERE event.id=run.outbox_event_id AND event.delivery_state='delivered'
    RETURNING event.id
  ) SELECT count(*) INTO validation_count FROM reset_events;

  WITH candidates AS (
    SELECT run.id,run.outbox_event_id FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id=run.outbox_event_id
    WHERE event.event_kind='document.reprocess_requested.v1'
      AND run.scope='search_index'
      AND (run.state='failed' OR (run.state='running' AND run.lease_expires_at<=now()))
    ORDER BY coalesce(run.lease_expires_at,run.failed_at,run.created_at)
    FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), reset_runs AS (
    UPDATE public.document_processing_runs AS run
    SET state='queued',stage='queued',started_at=NULL,failed_at=NULL,
        safe_error_code='work_requeued',lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE run.id=candidate.id RETURNING candidate.outbox_event_id
  ), reset_events AS (
    UPDATE public.outbox_events AS event
    SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,
        lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now()
    FROM reset_runs AS run WHERE event.id=run.outbox_event_id AND event.delivery_state='delivered'
    RETURNING event.id
  ) SELECT count(*) INTO processing_count FROM reset_events;

  WITH candidates AS (
    SELECT run.id,run.org_id,
      CASE WHEN event.event_kind='document.reprocess_requested.v1'
        THEN 'scoped_reprocess_replay_unsafe' ELSE 'legacy_processing_replay_unsafe' END AS reason
    FROM public.document_processing_runs AS run
    JOIN public.outbox_events AS event ON event.id=run.outbox_event_id
    WHERE run.outbox_event_id IS NOT NULL
      AND NOT (event.event_kind='document.reprocess_requested.v1' AND run.scope='search_index')
      AND (run.state='failed' OR (run.state='running' AND run.lease_expires_at<=now()))
    ORDER BY coalesce(run.lease_expires_at,run.failed_at,run.created_at)
    FOR UPDATE OF run SKIP LOCKED LIMIT p_batch_size
  ), fenced AS (
    UPDATE public.document_processing_runs AS run
    SET state='failed',stage=CASE WHEN candidate.reason='scoped_reprocess_replay_unsafe'
          THEN 'review'::public.document_processing_stage ELSE 'failed'::public.document_processing_stage END,
        failed_at=coalesce(run.failed_at,now()),safe_error_code=CASE
          WHEN candidate.reason='scoped_reprocess_replay_unsafe' THEN 'scoped_reprocess_replay_unsafe'
          ELSE 'legacy_processing_recovery_required'
        END,
        lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
    FROM candidates AS candidate WHERE run.id=candidate.id
    RETURNING run.id,run.org_id,candidate.reason
  )
  INSERT INTO public.document_processing_recovery_cases(org_id,processing_run_id,recovery_reason)
  SELECT org_id,id,reason FROM fenced
  ON CONFLICT (processing_run_id) DO UPDATE SET updated_at=now();

  RETURN QUERY SELECT validation_count,processing_count;
END $$;

REVOKE ALL ON FUNCTION public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_document_reprocess(uuid,public.document_processing_scope,uuid,integer)
  TO authenticated;
REVOKE ALL ON FUNCTION public.organisation_member_capabilities(public.org_member_role,boolean,public.organisation_membership_state)
  FROM PUBLIC, anon;

COMMIT;
