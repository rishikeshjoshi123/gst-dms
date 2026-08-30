-- Fenced creation-time Trash effect. The hierarchy command already emits this
-- identifier-only event; complete its dispatch contract without expanding the
-- event payload or exposing any Trash state to browser/service table access.
BEGIN;

CREATE TABLE public.trash_operation_created_effect_receipts (
  event_id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  event_kind text NOT NULL CHECK (event_kind = 'trash.operation_created.v1'),
  outcome_code text NOT NULL CHECK (outcome_code IN (
    'operation_semantic_index_invalidated', 'operation_no_longer_trashed'
  )),
  affected_count integer NOT NULL CHECK (affected_count >= 0),
  handled_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trash_operation_created_effect_receipts_event_org_fkey
    FOREIGN KEY (org_id, event_id) REFERENCES public.outbox_events(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_operation_created_effect_receipts_operation_org_fkey
    FOREIGN KEY (org_id, operation_id) REFERENCES public.trash_operations(org_id, id) ON DELETE RESTRICT
);
ALTER TABLE public.trash_operation_created_effect_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_operation_created_effect_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_operation_created_effect_receipts FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.handle_trash_operation_created_effect(
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
  prior public.trash_operation_created_effect_receipts%ROWTYPE;
  affected integer := 0;
  effect_outcome text;
BEGIN
  IF p_event_id IS NULL OR p_expected_org_id IS NULL OR p_delivery_lease_token IS NULL
     OR p_expected_event_kind <> 'trash.operation_created.v1' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::text,0; RETURN;
  END IF;

  SELECT outbox.* INTO event_row FROM public.outbox_events outbox
  WHERE outbox.id=p_event_id FOR UPDATE;
  IF event_row.id IS NULL OR event_row.org_id IS DISTINCT FROM p_expected_org_id
     OR event_row.event_kind IS DISTINCT FROM p_expected_event_kind
     OR event_row.aggregate_type <> 'trash_operation'
     OR event_row.delivery_state <> 'leased'
     OR event_row.lease_token IS DISTINCT FROM p_delivery_lease_token
     OR event_row.lease_expires_at <= now()
     OR jsonb_typeof(event_row.payload) <> 'object'
     OR NOT pg_input_is_valid(event_row.payload->>'operation_id', 'uuid')
     OR NOT pg_input_is_valid(event_row.payload->>'root_resource_id', 'uuid')
     OR event_row.payload IS DISTINCT FROM jsonb_build_object(
       'operation_id', event_row.aggregate_id::text,
       'root_resource_id', event_row.payload->>'root_resource_id',
       'root_resource_type', event_row.payload->>'root_resource_type'
     )
     OR event_row.payload->>'root_resource_type' NOT IN ('client','matter','document') THEN
    RETURN QUERY SELECT 'invalid_event'::text,NULL::text,0; RETURN;
  END IF;

  SELECT receipt.* INTO prior FROM public.trash_operation_created_effect_receipts receipt
  WHERE receipt.event_id=event_row.id;
  IF prior.event_id IS NOT NULL THEN
    RETURN QUERY SELECT 'already_handled'::text,prior.outcome_code,prior.affected_count; RETURN;
  END IF;

  -- Match the command/Restore serialisation boundary. A Restore either waits
  -- for this invalidation, or wins first and preserves its rebuilt embedding.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(event_row.org_id::text), pg_catalog.hashtext('hierarchical-resource-trash')
  );
  SELECT target.* INTO operation FROM public.trash_operations target
  WHERE target.org_id=event_row.org_id AND target.id=event_row.aggregate_id FOR UPDATE;
  IF operation.id IS NULL
     OR operation.root_resource_id::text IS DISTINCT FROM event_row.payload->>'root_resource_id'
     OR operation.root_resource_type::text IS DISTINCT FROM event_row.payload->>'root_resource_type' THEN
    RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
  END IF;

  IF operation.state='restored' THEN
    IF EXISTS (
      SELECT 1 FROM public.resource_trash_memberships membership
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
        AND membership.state<>'restored'
    ) THEN
      RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
    END IF;
    IF (SELECT count(*) FROM public.resource_trash_memberships membership
        WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
          AND membership.state='restored') <> operation.included_client_count
            + operation.included_matter_count + operation.included_document_count
       OR NOT EXISTS (
         SELECT 1 FROM public.resource_trash_memberships membership
         WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
           AND membership.resource_type=operation.root_resource_type
           AND membership.resource_id=operation.root_resource_id
           AND membership.cause='direct' AND membership.parent_membership_id IS NULL
           AND membership.state='restored'
       ) THEN
      RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
    END IF;
    effect_outcome := 'operation_no_longer_trashed';
  ELSIF operation.state IN ('trashed','restore_blocked','purge_scheduled') THEN
    -- Do not infer a membership from the root alone. Every active member must
    -- still belong to this operation, including the exact direct root.
    IF (SELECT count(*) FROM public.resource_trash_memberships membership
        WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
          AND membership.state='active') <> operation.included_client_count
            + operation.included_matter_count + operation.included_document_count
       OR EXISTS (
         SELECT 1 FROM public.resource_trash_memberships membership
         WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
           AND membership.state<>'active'
       )
       OR NOT EXISTS (
         SELECT 1 FROM public.resource_trash_memberships membership
         WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
           AND membership.resource_type=operation.root_resource_type
           AND membership.resource_id=operation.root_resource_id
           AND membership.cause='direct' AND membership.parent_membership_id IS NULL
           AND membership.state='active'
       ) THEN
      RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
    END IF;

    WITH candidates AS (
      SELECT document.id
      FROM public.resource_trash_memberships membership
      JOIN public.documents document
        ON membership.resource_type='document' AND document.org_id=membership.org_id
        AND document.id=membership.resource_id
      WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
        AND membership.state='active' AND document.record_state='trashed'
        AND document.deleted_at IS NOT NULL AND document.active_trash_membership_id=membership.id
      ORDER BY document.id FOR UPDATE OF document
    )
    UPDATE public.documents document SET
      embedding=NULL, embedding_model=NULL, embedding_version=NULL,
      embedding_document_version_id=NULL
    FROM candidates
    WHERE document.org_id=operation.org_id AND document.id=candidates.id;
    GET DIAGNOSTICS affected = ROW_COUNT;
    effect_outcome := 'operation_semantic_index_invalidated';
  ELSE
    RETURN QUERY SELECT 'state_mismatch'::text,NULL::text,0; RETURN;
  END IF;

  INSERT INTO public.trash_operation_created_effect_receipts(
    event_id,org_id,operation_id,event_kind,outcome_code,affected_count
  ) VALUES (
    event_row.id,event_row.org_id,operation.id,event_row.event_kind,effect_outcome,affected
  );
  RETURN QUERY SELECT 'handled'::text,effect_outcome,affected;
END $$;

-- A Trigger queue acceptance is not success for the creation-time effect.
-- Keep all prior fences and require this distinct private receipt as well.
CREATE OR REPLACE FUNCTION public.ack_document_outbox_event(
  p_event_id uuid,
  p_lease_token uuid,
  p_trigger_run_id text
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE event_row public.outbox_events%ROWTYPE;
BEGIN
  IF p_event_id IS NULL OR p_lease_token IS NULL OR p_trigger_run_id IS NULL
     OR p_trigger_run_id !~ '^[A-Za-z0-9._:-]{1,200}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT outbox.* INTO event_row FROM public.outbox_events outbox WHERE outbox.id=p_event_id FOR UPDATE;
  IF event_row.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text; RETURN; END IF;
  IF event_row.delivery_state='delivered' THEN
    RETURN QUERY SELECT CASE WHEN event_row.trigger_run_id=p_trigger_run_id THEN 'already_accepted'::text ELSE 'delivery_already_complete'::text END;
    RETURN;
  END IF;
  IF event_row.delivery_state<>'leased' OR event_row.lease_token IS DISTINCT FROM p_lease_token
     OR event_row.lease_expires_at<=now() THEN RETURN QUERY SELECT 'stale_lease'::text; RETURN; END IF;
  IF event_row.event_kind='trash.operation_created.v1' AND NOT EXISTS (
    SELECT 1 FROM public.trash_operation_created_effect_receipts receipt
    WHERE receipt.org_id=event_row.org_id AND receipt.event_id=event_row.id AND receipt.event_kind=event_row.event_kind
  ) THEN RETURN QUERY SELECT 'effect_not_handled'::text; RETURN; END IF;
  IF event_row.event_kind IN ('trash.operation_restored.v1','trash.search_reindex_requested.v1','trash.schedule_reevaluation_requested.v1')
     AND NOT EXISTS (
       SELECT 1 FROM public.trash_restore_effect_receipts receipt
       WHERE receipt.org_id=event_row.org_id AND receipt.event_id=event_row.id AND receipt.event_kind=event_row.event_kind
     ) THEN RETURN QUERY SELECT 'effect_not_handled'::text; RETURN; END IF;
  UPDATE public.outbox_events outbox SET delivery_state='delivered',lease_token=NULL,lease_expires_at=NULL,
    delivered_at=now(),trigger_run_id=p_trigger_run_id,last_error_code=NULL,updated_at=now() WHERE outbox.id=event_row.id;
  INSERT INTO public.outbox_dispatch_attempts(event_id,org_id,attempt_number,lease_fingerprint,outcome,trigger_run_id)
  VALUES(event_row.id,event_row.org_id,event_row.attempt_count,encode(extensions.digest(p_lease_token::text,'sha256'),'hex'),'accepted',p_trigger_run_id);
  RETURN QUERY SELECT 'ok'::text;
END $$;

REVOKE ALL ON FUNCTION public.handle_trash_operation_created_effect(uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_trash_operation_created_effect(uuid,uuid,uuid,text) TO service_role;

COMMENT ON TABLE public.trash_operation_created_effect_receipts IS
  'Private content-free receipt for a fenced Trash creation semantic-index invalidation.';
COMMENT ON FUNCTION public.handle_trash_operation_created_effect(uuid,uuid,uuid,text) IS
  'Service-only leased Trash creation consumer. Revalidates immutable operation identity and lifecycle, clears only semantic index provenance for active operation-owned trashed documents, and records one receipt.';

COMMIT;
