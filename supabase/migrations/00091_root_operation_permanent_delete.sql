-- Root-operation permanent deletion: immutable impact, governed confirmation,
-- durable execution, external-storage reconciliation, and content-free receipts.
BEGIN;

CREATE TYPE public.trash_purge_source AS ENUM ('manual','retention_schedule');
CREATE TYPE public.trash_purge_job_state AS ENUM (
  'queued','running','waiting_storage','retryable','blocked','completed'
);
CREATE TYPE public.trash_purge_storage_state AS ENUM ('pending','leased','deleted');
CREATE TYPE public.trash_purge_blocker_kind AS ENUM ('active_export','active_backup','platform_dependency');
CREATE TYPE public.trash_purge_blocker_state AS ENUM ('active','released');
ALTER TYPE public.document_content_availability ADD VALUE IF NOT EXISTS 'purged';

CREATE TABLE public.trash_purge_blockers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  resource_type public.trash_resource_type NOT NULL,
  resource_id uuid NOT NULL,
  blocker_kind public.trash_purge_blocker_kind NOT NULL,
  state public.trash_purge_blocker_state NOT NULL DEFAULT 'active',
  opaque_reference uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  CONSTRAINT trash_purge_blockers_operation_org_fkey FOREIGN KEY (org_id,operation_id)
    REFERENCES public.trash_operations(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT trash_purge_blockers_state_shape CHECK (
    (state='active' AND released_at IS NULL) OR (state='released' AND released_at IS NOT NULL)
  ),
  CONSTRAINT trash_purge_blockers_subject_unique UNIQUE (org_id,operation_id,blocker_kind,opaque_reference)
);
CREATE INDEX trash_purge_blockers_active_operation_idx
  ON public.trash_purge_blockers(org_id,operation_id,resource_type,resource_id)
  WHERE state='active';

CREATE TABLE public.trash_purge_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  source public.trash_purge_source NOT NULL,
  state public.trash_purge_job_state NOT NULL DEFAULT 'queued',
  impact_fingerprint text NOT NULL CHECK (impact_fingerprint ~ '^[0-9a-f]{64}$'),
  confirmed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  confirmed_at timestamptz,
  idempotency_key text,
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 20),
  lease_token uuid,
  lease_expires_at timestamptz,
  safe_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  database_prepared_at timestamptz,
  completed_at timestamptz,
  CONSTRAINT trash_purge_jobs_operation_org_fkey FOREIGN KEY (org_id,operation_id)
    REFERENCES public.trash_operations(org_id,id) ON DELETE RESTRICT,
  CONSTRAINT trash_purge_jobs_one_operation UNIQUE (operation_id),
  CONSTRAINT trash_purge_jobs_manual_shape CHECK (
    (source='manual' AND confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL AND idempotency_key IS NOT NULL)
    OR (source='retention_schedule' AND confirmed_by IS NULL AND confirmed_at IS NULL AND idempotency_key IS NULL)
  ),
  CONSTRAINT trash_purge_jobs_lease_shape CHECK (
    (state='running' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR (state<>'running' AND lease_token IS NULL AND lease_expires_at IS NULL)
  ),
  CONSTRAINT trash_purge_jobs_completion_shape CHECK (
    (state='completed' AND completed_at IS NOT NULL) OR (state<>'completed' AND completed_at IS NULL)
  )
);
CREATE UNIQUE INDEX trash_purge_jobs_actor_key_unique
  ON public.trash_purge_jobs(org_id,confirmed_by,idempotency_key)
  WHERE source='manual';
CREATE INDEX trash_purge_jobs_claim_idx ON public.trash_purge_jobs(state,created_at,id)
  WHERE state IN ('queued','retryable','waiting_storage','running');

CREATE TABLE public.trash_purge_storage_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  job_id uuid NOT NULL REFERENCES public.trash_purge_jobs(id) ON DELETE RESTRICT,
  asset_id uuid,
  bucket_id text,
  object_key text,
  state public.trash_purge_storage_state NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 20),
  lease_token uuid,
  lease_expires_at timestamptz,
  safe_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT trash_purge_storage_private_locator CHECK (
    (state IN ('pending','leased') AND bucket_id='documents' AND btrim(object_key)<>'' AND deleted_at IS NULL)
    OR (state='deleted' AND bucket_id IS NULL AND object_key IS NULL AND deleted_at IS NOT NULL)
  ),
  CONSTRAINT trash_purge_storage_lease_shape CHECK (
    (state='leased' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL)
    OR (state<>'leased' AND lease_token IS NULL AND lease_expires_at IS NULL)
  ),
  CONSTRAINT trash_purge_storage_asset_unique UNIQUE (job_id,asset_id)
);
CREATE INDEX trash_purge_storage_claim_idx
  ON public.trash_purge_storage_deletions(job_id,state,created_at,id)
  WHERE state IN ('pending','leased');

CREATE TABLE public.trash_purge_execution_fences (
  transaction_id bigint PRIMARY KEY,
  job_id uuid NOT NULL REFERENCES public.trash_purge_jobs(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One content-free projection owns hold, export/backup, and legacy dependency
-- scope semantics for every impact, confirmation, claim, and execution check.
CREATE FUNCTION public.trash_purge_active_blockers(p_org_id uuid,p_operation_id uuid)
RETURNS TABLE(blocker_id uuid,code text,resource_type public.trash_resource_type,resource_id uuid)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  WITH target AS (
    SELECT operation.*,
      coalesce(root_client.id,root_matter.client_id,root_document_matter.client_id) ancestor_client_id,
      coalesce(root_matter.id,root_document.matter_id) ancestor_matter_id
    FROM public.trash_operations operation
    LEFT JOIN public.clients root_client ON operation.root_resource_type='client' AND root_client.org_id=operation.org_id AND root_client.id=operation.root_resource_id
    LEFT JOIN public.matters root_matter ON operation.root_resource_type='matter' AND root_matter.org_id=operation.org_id AND root_matter.id=operation.root_resource_id
    LEFT JOIN public.documents root_document ON operation.root_resource_type='document' AND root_document.org_id=operation.org_id AND root_document.id=operation.root_resource_id
    LEFT JOIN public.matters root_document_matter ON root_document_matter.org_id=root_document.org_id AND root_document_matter.id=root_document.matter_id
    WHERE operation.org_id=p_org_id AND operation.id=p_operation_id
  ), members AS (
    SELECT membership.resource_type,membership.resource_id FROM public.resource_trash_memberships membership
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
  )
  SELECT hold.id,'legal_hold'::text,hold.resource_type,hold.resource_id
  FROM public.resource_holds hold CROSS JOIN target
  WHERE hold.org_id=p_org_id AND hold.state='active' AND (
    EXISTS (SELECT 1 FROM members member WHERE member.resource_type=hold.resource_type AND member.resource_id=hold.resource_id)
    OR (hold.scope='subtree' AND (
      (hold.resource_type='client' AND hold.resource_id=target.ancestor_client_id)
      OR (hold.resource_type='matter' AND hold.resource_id=target.ancestor_matter_id)
    ))
  )
  UNION ALL
  SELECT blocker.id,blocker.blocker_kind::text,blocker.resource_type,blocker.resource_id
  FROM public.trash_purge_blockers blocker
  WHERE blocker.org_id=p_org_id AND blocker.operation_id=p_operation_id AND blocker.state='active'
  UNION ALL
  SELECT supporting.id,'platform_dependency'::text,'matter'::public.trash_resource_type,supporting.matter_id
  FROM public.supporting_documents supporting
  JOIN members member ON member.resource_type='matter' AND member.resource_id=supporting.matter_id
  WHERE supporting.org_id=p_org_id
$$;

-- All legitimate blocker/hold/deprecated-supporting-document writers serialize
-- with preparation. A dependency that loses that race is rejected after the
-- database boundary has become irreversible.
CREATE FUNCTION public.trash_purge_dependency_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(NEW.org_id::text),pg_catalog.hashtext('trash-purge-dependencies'));
  IF EXISTS (
    SELECT 1 FROM public.trash_purge_jobs job
    WHERE job.org_id=NEW.org_id AND job.database_prepared_at IS NOT NULL AND job.state<>'completed'
      AND EXISTS (SELECT 1 FROM public.trash_purge_active_blockers(job.org_id,job.operation_id) blocker WHERE blocker.blocker_id=NEW.id)
  ) THEN RAISE EXCEPTION 'dependency cannot attach after permanent-delete preparation'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER resource_holds_purge_dependency_guard
  AFTER INSERT OR UPDATE ON public.resource_holds FOR EACH ROW EXECUTE FUNCTION public.trash_purge_dependency_write_guard();
CREATE TRIGGER supporting_documents_purge_dependency_guard
  AFTER INSERT OR UPDATE ON public.supporting_documents FOR EACH ROW EXECUTE FUNCTION public.trash_purge_dependency_write_guard();
CREATE TRIGGER trash_purge_blockers_dependency_guard
  AFTER INSERT OR UPDATE ON public.trash_purge_blockers FOR EACH ROW EXECUTE FUNCTION public.trash_purge_dependency_write_guard();

-- Canonical resources are retained as opaque purged shells, and the legacy
-- supporting-document store is a fail-closed platform dependency. Neither has
-- an authorised physical row-delete path. This also stops historical CASCADE
-- foreign keys from becoming a service-role hard-delete bypass.
CREATE FUNCTION public.managed_resource_prevent_hard_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  RAISE EXCEPTION 'managed resources require the governed Trash lifecycle';
END $$;
CREATE TRIGGER clients_no_hard_delete BEFORE DELETE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.managed_resource_prevent_hard_delete();
CREATE TRIGGER matters_no_hard_delete BEFORE DELETE ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.managed_resource_prevent_hard_delete();
CREATE TRIGGER documents_no_hard_delete BEFORE DELETE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.managed_resource_prevent_hard_delete();
CREATE TRIGGER supporting_documents_no_hard_delete BEFORE DELETE ON public.supporting_documents
  FOR EACH ROW EXECUTE FUNCTION public.managed_resource_prevent_hard_delete();
REVOKE DELETE,TRUNCATE ON TABLE public.clients,public.matters,public.documents,public.supporting_documents
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.trash_purge_dependency_write_guard(),public.managed_resource_prevent_hard_delete()
  FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE public.trash_purge_tombstones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  operation_id uuid NOT NULL,
  job_id uuid NOT NULL REFERENCES public.trash_purge_jobs(id) ON DELETE RESTRICT,
  resource_type public.trash_resource_type NOT NULL,
  former_resource_id uuid NOT NULL,
  source public.trash_purge_source NOT NULL,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  verification_code text NOT NULL CHECK (verification_code IN ('database_and_storage_verified','database_only_verified')),
  purged_at timestamptz NOT NULL,
  CONSTRAINT trash_purge_tombstones_operation_resource_unique UNIQUE (operation_id,resource_type,former_resource_id)
);

CREATE TABLE public.trash_purge_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (idempotency_key ~ '^[a-z][a-z0-9_.:-]{0,127}$'),
  operation_id uuid NOT NULL,
  job_id uuid,
  result_code text NOT NULL CHECK (result_code IN (
    'queued','already_queued','retried','blocked','stale_impact','not_available','not_allowed','recent_auth_required','confirmation_mismatch'
  )),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trash_purge_command_receipts_subject_unique UNIQUE (org_id,actor_user_id,idempotency_key)
);

ALTER TABLE public.trash_purge_blockers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_blockers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_jobs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_storage_deletions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_storage_deletions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_execution_fences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_execution_fences FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_tombstones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_tombstones FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_command_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_purge_blockers,public.trash_purge_jobs,
  public.trash_purge_storage_deletions,public.trash_purge_tombstones,
  public.trash_purge_command_receipts,public.trash_purge_execution_fences FROM PUBLIC,anon,authenticated,service_role;

-- Existing lifecycle tables are fail-closed against deletion. A transaction
-- fence can be created only after a valid purge job lease is checked inside
-- the service-owned functions below; a caller-settable GUC is never trusted.
CREATE OR REPLACE FUNCTION public.document_lifecycle_prevent_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF session_user='postgres' AND TG_TABLE_NAME='outbox_events'
     AND current_setting('document_lifecycle.outbox_compaction_delete',true)='on' THEN RETURN OLD; END IF;
  IF EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current())
     AND TG_TABLE_NAME IN ('file_assets','document_versions','source_analysis_runs','document_version_analysis_bindings','storage_reservations') THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'lifecycle records are retained until the authorised purge boundary';
END $$;

CREATE OR REPLACE FUNCTION public.source_analysis_provenance_prevent_attempt_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current()) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'source analysis attempts are retained until the authorised purge boundary';
END $$;

CREATE OR REPLACE FUNCTION public.prevent_activity_log_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='UPDATE'
     AND EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current())
     AND NEW.id=OLD.id AND NEW.org_id=OLD.org_id AND NEW.entity_type=OLD.entity_type
     AND NEW.entity_id IS NOT DISTINCT FROM OLD.entity_id AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id
     AND NEW.created_at=OLD.created_at AND NEW.action='resource_purged'
     AND NEW.description IS NULL AND NEW.metadata='{}'::jsonb AND NOT NEW.is_reversible
     AND NEW.reversed_by IS NULL AND NEW.reversed_at IS NULL THEN RETURN NEW;
  END IF;
  RAISE EXCEPTION 'activity logs are append-only';
END $$;

CREATE OR REPLACE FUNCTION public.source_field_candidate_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current()) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'source field candidates are immutable once materialized';
END $$;
CREATE OR REPLACE FUNCTION public.document_field_candidate_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current()) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'document field candidates are immutable once materialized';
END $$;
CREATE OR REPLACE FUNCTION public.document_field_decision_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND EXISTS (SELECT 1 FROM public.trash_purge_execution_fences fence WHERE fence.transaction_id=txid_current()) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'document field decisions are append-only and immutable';
END $$;

-- A blocker registration is service-owned and must point at a current member
-- of the exact root operation. Browser/service-role table DML remains denied.
CREATE FUNCTION public.register_trash_purge_blocker(
  p_operation_id uuid,p_resource_type public.trash_resource_type,p_resource_id uuid,
  p_blocker_kind public.trash_purge_blocker_kind,p_opaque_reference uuid,p_active boolean
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE;
BEGIN
  IF p_operation_id IS NULL OR p_resource_type IS NULL OR p_resource_id IS NULL
     OR p_blocker_kind IS NULL OR p_opaque_reference IS NULL OR p_active IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id FOR UPDATE;
  IF operation.id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id
      AND membership.resource_type=p_resource_type AND membership.resource_id=p_resource_id
  ) THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('trash-purge-dependencies'));
  IF EXISTS (SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=operation.id AND job.database_prepared_at IS NOT NULL)
     OR operation.state='purged' THEN
    RETURN QUERY SELECT 'not_available'::text; RETURN;
  END IF;
  INSERT INTO public.trash_purge_blockers(
    org_id,operation_id,resource_type,resource_id,blocker_kind,opaque_reference,state,released_at
  ) VALUES (
    operation.org_id,operation.id,p_resource_type,p_resource_id,p_blocker_kind,p_opaque_reference,
    CASE WHEN p_active THEN 'active'::public.trash_purge_blocker_state ELSE 'released'::public.trash_purge_blocker_state END,
    CASE WHEN p_active THEN NULL ELSE now() END
  ) ON CONFLICT (org_id,operation_id,blocker_kind,opaque_reference) DO UPDATE SET
    resource_type=excluded.resource_type,
    resource_id=excluded.resource_id,state=excluded.state,released_at=excluded.released_at;
  RETURN QUERY SELECT CASE WHEN p_active THEN 'active' ELSE 'released' END::text;
END $$;

-- Immutable impact fingerprint. It deliberately includes every mutable fact
-- that can change purge eligibility or asset ownership, but no display text.
CREATE FUNCTION public.trash_purge_impact_fingerprint(p_org_id uuid,p_operation_id uuid)
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  WITH members AS (
    SELECT membership.resource_type,membership.resource_id,membership.state,
      CASE membership.resource_type
        WHEN 'client' THEN (SELECT client.record_state::text FROM public.clients client WHERE client.org_id=membership.org_id AND client.id=membership.resource_id)
        WHEN 'matter' THEN (SELECT matter.record_state::text FROM public.matters matter WHERE matter.org_id=membership.org_id AND matter.id=membership.resource_id)
        ELSE (SELECT document.record_state::text||':'||document.lifecycle_revision::text FROM public.documents document WHERE document.org_id=membership.org_id AND document.id=membership.resource_id)
      END resource_revision
    FROM public.resource_trash_memberships membership
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
  ), purge_documents AS (
    SELECT resource_id document_id FROM members WHERE resource_type='document'
  ), owned_intakes AS (
    SELECT assignment.intake_item_id FROM public.intake_item_assignments assignment
    WHERE assignment.org_id=p_org_id AND EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=assignment.document_id)
      AND NOT EXISTS (SELECT 1 FROM public.intake_item_assignments other_assignment
        WHERE other_assignment.org_id=assignment.org_id AND other_assignment.intake_item_id=assignment.intake_item_id
          AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=other_assignment.document_id))
  ), assets AS (
    SELECT DISTINCT asset.id,asset.byte_size,
      EXISTS (SELECT 1 FROM public.document_versions other_version
        WHERE other_version.org_id=p_org_id AND other_version.asset_id=asset.id
          AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=other_version.document_id))
      OR EXISTS (SELECT 1 FROM public.intake_items intake
        WHERE intake.org_id=p_org_id AND intake.asset_id=asset.id
          AND NOT EXISTS (SELECT 1 FROM public.intake_item_assignments assignment
            JOIN purge_documents owned ON owned.document_id=assignment.document_id
            WHERE assignment.org_id=intake.org_id AND assignment.intake_item_id=intake.id))
      OR EXISTS (SELECT 1 FROM public.staged_document_backfill_items staged
        WHERE staged.org_id=p_org_id AND (staged.canonical_asset_id=asset.id OR staged.duplicate_asset_id=asset.id))
      OR EXISTS (SELECT 1 FROM public.source_analysis_runs run WHERE run.org_id=p_org_id AND run.asset_id=asset.id AND (
        NOT EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
          JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id AND bound_version.id=binding.document_version_id
          WHERE binding.org_id=p_org_id AND binding.source_analysis_run_id=run.id
            AND EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=bound_version.document_id))
        OR EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
          JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id AND bound_version.id=binding.document_version_id
          WHERE binding.org_id=p_org_id AND binding.source_analysis_run_id=run.id
            AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=bound_version.document_id))
      ))
      OR EXISTS (SELECT 1 FROM public.upload_sessions session WHERE session.org_id=p_org_id AND session.asset_id=asset.id
        AND NOT EXISTS (SELECT 1 FROM public.intake_items intake WHERE intake.org_id=session.org_id
          AND intake.upload_session_id=session.id AND EXISTS (SELECT 1 FROM owned_intakes owned WHERE owned.intake_item_id=intake.id))) AS shared
    FROM purge_documents owned
    JOIN public.document_versions version ON version.org_id=p_org_id AND version.document_id=owned.document_id
    JOIN public.file_assets asset ON asset.org_id=version.org_id AND asset.id=version.asset_id
  ), blockers AS (
    SELECT blocker.* FROM public.trash_purge_active_blockers(p_org_id,p_operation_id) blocker
  )
  SELECT encode(extensions.digest(convert_to(concat_ws('|',
    p_org_id::text,p_operation_id::text,
    coalesce((SELECT string_agg(resource_type::text||':'||resource_id::text||':'||state::text||':'||coalesce(resource_revision,''),',' ORDER BY resource_type,resource_id) FROM members),''),
    coalesce((SELECT string_agg(id::text||':'||byte_size::text||':'||shared::text,',' ORDER BY id) FROM assets),''),
    coalesce((SELECT string_agg(blocker_id::text||':'||code,',' ORDER BY blocker_id,code) FROM blockers),'')
  ),'utf8'),'sha256'),'hex')
$$;

CREATE OR REPLACE FUNCTION public.get_trash_purge_impact(p_operation_id uuid)
RETURNS TABLE(
  code text,operation_id uuid,root_resource_type public.trash_resource_type,root_resource_id uuid,
  root_name text,confirmation_text text,included_client_count integer,included_matter_count integer,
  included_document_count integer,unique_bytes bigint,shared_bytes_retained bigint,
  hold_count integer,active_export_count integer,blocker_count integer,blockers jsonb,
  can_purge boolean,requires_recent_auth boolean,impact_fingerprint text,impact_version integer,
  operation_state public.trash_operation_state,job_state public.trash_purge_job_state,
  job_safe_error_code text,scheduled_permanent_deletion_at timestamptz,purged_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE; caller record; display_name text; confirm_text text;
DECLARE unique_total bigint:=0; shared_total bigint:=0; holds integer:=0; exports integer:=0; blockers_total integer:=0;
DECLARE blocker_rows jsonb:='[]'::jsonb; current_job public.trash_purge_jobs%ROWTYPE;
BEGIN
  IF p_operation_id IS NULL OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN RETURN; END IF;
  IF operation.root_resource_type='client' THEN
    SELECT client.name,coalesce(nullif(client.gstin,''),nullif(client.pan,''),client.name)
      INTO display_name,confirm_text FROM public.clients client WHERE client.org_id=operation.org_id AND client.id=operation.root_resource_id;
  ELSIF operation.root_resource_type='matter' THEN
    SELECT matter.title,coalesce(nullif(matter.matter_code,''),matter.title)
      INTO display_name,confirm_text FROM public.matters matter WHERE matter.org_id=operation.org_id AND matter.id=operation.root_resource_id;
  ELSE
    SELECT coalesce(nullif(document.display_title,''),nullif(document.effective_filename,''),nullif(document.reference_number,''),'Document'),
      coalesce(nullif(document.display_title,''),nullif(document.effective_filename,''),nullif(document.reference_number,''),'DOCUMENT-'||document.id::text)
      INTO display_name,confirm_text FROM public.documents document WHERE document.org_id=operation.org_id AND document.id=operation.root_resource_id;
  END IF;
  WITH purge_documents AS (
    SELECT membership.resource_id document_id FROM public.resource_trash_memberships membership
    WHERE membership.org_id=operation.org_id AND membership.operation_id=operation.id AND membership.resource_type='document'
  ), owned_intakes AS (
    SELECT assignment.intake_item_id FROM public.intake_item_assignments assignment
    WHERE assignment.org_id=operation.org_id AND EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=assignment.document_id)
      AND NOT EXISTS (SELECT 1 FROM public.intake_item_assignments other_assignment
        WHERE other_assignment.org_id=assignment.org_id AND other_assignment.intake_item_id=assignment.intake_item_id
          AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=other_assignment.document_id))
  ), assets AS (
    SELECT DISTINCT asset.id,asset.byte_size,
      EXISTS (SELECT 1 FROM public.document_versions other_version WHERE other_version.org_id=operation.org_id
        AND other_version.asset_id=asset.id AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=other_version.document_id))
      OR EXISTS (SELECT 1 FROM public.intake_items intake WHERE intake.org_id=operation.org_id AND intake.asset_id=asset.id
        AND NOT EXISTS (SELECT 1 FROM public.intake_item_assignments assignment JOIN purge_documents owned ON owned.document_id=assignment.document_id
          WHERE assignment.org_id=intake.org_id AND assignment.intake_item_id=intake.id))
      OR EXISTS (SELECT 1 FROM public.staged_document_backfill_items staged WHERE staged.org_id=operation.org_id
        AND (staged.canonical_asset_id=asset.id OR staged.duplicate_asset_id=asset.id))
      OR EXISTS (SELECT 1 FROM public.source_analysis_runs run WHERE run.org_id=operation.org_id AND run.asset_id=asset.id AND (
        NOT EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
          JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id AND bound_version.id=binding.document_version_id
          WHERE binding.org_id=operation.org_id AND binding.source_analysis_run_id=run.id
            AND EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=bound_version.document_id))
        OR EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
          JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id AND bound_version.id=binding.document_version_id
          WHERE binding.org_id=operation.org_id AND binding.source_analysis_run_id=run.id
            AND NOT EXISTS (SELECT 1 FROM purge_documents owned WHERE owned.document_id=bound_version.document_id))
      ))
      OR EXISTS (SELECT 1 FROM public.upload_sessions session WHERE session.org_id=operation.org_id AND session.asset_id=asset.id
        AND NOT EXISTS (SELECT 1 FROM public.intake_items intake WHERE intake.org_id=session.org_id
          AND intake.upload_session_id=session.id AND EXISTS (SELECT 1 FROM owned_intakes owned WHERE owned.intake_item_id=intake.id))) shared
    FROM purge_documents owned JOIN public.document_versions version ON version.org_id=operation.org_id AND version.document_id=owned.document_id
    JOIN public.file_assets asset ON asset.org_id=version.org_id AND asset.id=version.asset_id
  ) SELECT coalesce(sum(byte_size) FILTER (WHERE NOT shared),0),coalesce(sum(byte_size) FILTER (WHERE shared),0)
    INTO unique_total,shared_total FROM assets;
  SELECT count(*) FILTER (WHERE blocker_projection.code='legal_hold')::integer,
    count(*) FILTER (WHERE blocker_projection.code='active_export')::integer,count(*)::integer
    INTO holds,exports,blockers_total
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id) blocker_projection;
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',safe_blockers.code,'resourceType',safe_blockers.resource_type,'resourceId',safe_blockers.resource_id)
    ORDER BY safe_blockers.code,safe_blockers.resource_type,safe_blockers.resource_id),'[]'::jsonb)
    INTO blocker_rows FROM public.trash_purge_active_blockers(operation.org_id,operation.id) safe_blockers;
  SELECT * INTO current_job FROM public.trash_purge_jobs job WHERE job.operation_id=operation.id;
  RETURN QUERY SELECT
    CASE WHEN operation.state='purged' THEN 'purged' WHEN operation.state IN ('purging','purge_failed') THEN 'in_progress' ELSE 'ready' END,
    operation.id,operation.root_resource_type,operation.root_resource_id,
    CASE WHEN operation.state='purged' THEN NULL ELSE display_name END,
    CASE WHEN operation.state='purged' THEN NULL ELSE confirm_text END,
    operation.included_client_count,operation.included_matter_count,operation.included_document_count,
    unique_total,shared_total,holds,exports,blockers_total,blocker_rows,
    (caller.is_owner OR caller.role='admin') AND operation.state IN ('trashed','restore_blocked','purge_scheduled','purge_failed')
      AND blockers_total=0,
    true,public.trash_purge_impact_fingerprint(operation.org_id,operation.id),1,
    operation.state,current_job.state,current_job.safe_error_code,operation.auto_purge_at,operation.purged_at;
END $$;

-- Manual confirmation binds recent authentication, the current exact phrase,
-- and the immutable impact fingerprint under the same hierarchy lock.
CREATE FUNCTION public.confirm_trash_purge(
  p_operation_id uuid,p_impact_fingerprint text,p_confirmation_text text,p_idempotency_key text
) RETURNS TABLE(code text,operation_id uuid,job_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE; caller record; expected_confirmation text;
DECLARE current_fingerprint text; prior public.trash_purge_command_receipts%ROWTYPE; existing public.trash_purge_jobs%ROWTYPE;
DECLARE created_job uuid; active_blockers integer;
BEGIN
  IF p_operation_id IS NULL OR p_impact_fingerprint !~ '^[0-9a-f]{64}$'
     OR p_confirmation_text IS NULL OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$' OR auth.uid() IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid; RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL OR NOT (caller.is_owner OR caller.role='admin') THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('hierarchical-resource-trash'));
  SELECT * INTO operation FROM public.trash_operations WHERE org_id=operation.org_id AND id=p_operation_id FOR UPDATE;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL OR NOT (caller.is_owner OR caller.role='admin') THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext(auth.uid()::text||':purge:'||p_idempotency_key));
  SELECT * INTO prior FROM public.trash_purge_command_receipts receipt WHERE receipt.org_id=operation.org_id
    AND receipt.actor_user_id=auth.uid() AND receipt.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.operation_id<>operation.id THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid;
    ELSE RETURN QUERY SELECT prior.result_code,operation.id,prior.job_id; END IF; RETURN;
  END IF;
  IF coalesce((auth.jwt()->>'iat')::bigint,0) < extract(epoch FROM now()-interval '10 minutes')::bigint THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,'recent_auth_required');
    RETURN QUERY SELECT 'recent_auth_required'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  IF operation.state NOT IN ('trashed','restore_blocked','purge_scheduled','purge_failed') THEN
    RETURN QUERY SELECT 'not_available'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  IF operation.root_resource_type='client' THEN SELECT coalesce(nullif(gstin,''),nullif(pan,''),name) INTO expected_confirmation FROM public.clients WHERE org_id=operation.org_id AND id=operation.root_resource_id;
  ELSIF operation.root_resource_type='matter' THEN SELECT coalesce(nullif(matter_code,''),title) INTO expected_confirmation FROM public.matters WHERE org_id=operation.org_id AND id=operation.root_resource_id;
  ELSE SELECT coalesce(nullif(display_title,''),nullif(effective_filename,''),nullif(reference_number,''),'DOCUMENT-'||id::text) INTO expected_confirmation FROM public.documents WHERE org_id=operation.org_id AND id=operation.root_resource_id; END IF;
  IF p_confirmation_text IS DISTINCT FROM expected_confirmation THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,'confirmation_mismatch');
    RETURN QUERY SELECT 'confirmation_mismatch'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  current_fingerprint:=public.trash_purge_impact_fingerprint(operation.org_id,operation.id);
  IF current_fingerprint IS DISTINCT FROM p_impact_fingerprint THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,'stale_impact');
    RETURN QUERY SELECT 'stale_impact'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  SELECT count(*)::integer INTO active_blockers
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
  IF active_blockers>0 THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,'blocked');
    RETURN QUERY SELECT 'blocked'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO existing FROM public.trash_purge_jobs job WHERE job.operation_id=operation.id;
  IF existing.id IS NOT NULL THEN
    IF existing.state='blocked' AND existing.database_prepared_at IS NULL THEN
      UPDATE public.trash_purge_jobs SET state='queued',source='manual',impact_fingerprint=current_fingerprint,
        confirmed_by=auth.uid(),confirmed_at=now(),idempotency_key=p_idempotency_key,safe_error_code=NULL
        WHERE id=existing.id;
      INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
        VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,existing.id,'queued');
      RETURN QUERY SELECT 'queued'::text,operation.id,existing.id; RETURN;
    END IF;
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,existing.id,'already_queued');
    RETURN QUERY SELECT 'already_queued'::text,operation.id,existing.id; RETURN;
  END IF;
  INSERT INTO public.trash_purge_jobs(org_id,operation_id,source,impact_fingerprint,confirmed_by,confirmed_at,idempotency_key)
    VALUES(operation.org_id,operation.id,'manual',current_fingerprint,auth.uid(),now(),p_idempotency_key) RETURNING id INTO created_job;
  INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
    VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,created_job,'queued');
  RETURN QUERY SELECT 'queued'::text,operation.id,created_job;
END $$;

-- Once database preparation has begun, the original typed phrase has been
-- intentionally scrubbed. Recovery therefore requires a fresh Owner/Admin
-- session and the exact current post-preparation impact, never a reused
-- pre-purge confirmation.
CREATE FUNCTION public.retry_trash_purge(
  p_operation_id uuid,p_impact_fingerprint text,p_idempotency_key text
) RETURNS TABLE(code text,operation_id uuid,job_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE; caller record; job public.trash_purge_jobs%ROWTYPE;
DECLARE prior public.trash_purge_command_receipts%ROWTYPE; current_fingerprint text; active_blockers integer:=0;
BEGIN
  IF p_operation_id IS NULL OR p_impact_fingerprint !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$' OR auth.uid() IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid; RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL OR NOT (caller.is_owner OR caller.role='admin') THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('hierarchical-resource-trash'));
  SELECT * INTO operation FROM public.trash_operations WHERE org_id=operation.org_id AND id=p_operation_id FOR UPDATE;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL OR NOT (caller.is_owner OR caller.role='admin') THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext(auth.uid()::text||':purge:'||p_idempotency_key));
  SELECT * INTO prior FROM public.trash_purge_command_receipts receipt
    WHERE receipt.org_id=operation.org_id AND receipt.actor_user_id=auth.uid() AND receipt.idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.operation_id<>operation.id THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid;
    ELSE RETURN QUERY SELECT prior.result_code,operation.id,prior.job_id; END IF; RETURN;
  END IF;
  IF coalesce((auth.jwt()->>'iat')::bigint,0) < extract(epoch FROM now()-interval '10 minutes')::bigint THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,'recent_auth_required');
    RETURN QUERY SELECT 'recent_auth_required'::text,operation.id,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO job FROM public.trash_purge_jobs existing WHERE existing.operation_id=operation.id FOR UPDATE;
  IF operation.state<>'purge_failed' OR job.id IS NULL OR job.database_prepared_at IS NULL
     OR job.completed_at IS NOT NULL OR job.state NOT IN ('blocked','retryable') THEN
    RETURN QUERY SELECT 'not_available'::text,operation.id,job.id; RETURN;
  END IF;
  current_fingerprint:=public.trash_purge_impact_fingerprint(operation.org_id,operation.id);
  IF current_fingerprint IS DISTINCT FROM p_impact_fingerprint THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,job.id,'stale_impact');
    RETURN QUERY SELECT 'stale_impact'::text,operation.id,job.id; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('trash-purge-dependencies'));
  SELECT count(*)::integer INTO active_blockers
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
  IF active_blockers>0 THEN
    INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
      VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,job.id,'blocked');
    RETURN QUERY SELECT 'blocked'::text,operation.id,job.id; RETURN;
  END IF;
  UPDATE public.trash_purge_storage_deletions deletion SET state='pending',attempt_count=0,lease_token=NULL,
    lease_expires_at=NULL,safe_error_code=NULL WHERE deletion.job_id=job.id AND deletion.state<>'deleted';
  UPDATE public.trash_purge_jobs SET state='retryable',attempt_count=0,lease_token=NULL,
    lease_expires_at=NULL,safe_error_code=NULL WHERE id=job.id;
  INSERT INTO public.trash_purge_command_receipts(org_id,actor_user_id,idempotency_key,operation_id,job_id,result_code)
    VALUES(operation.org_id,auth.uid(),p_idempotency_key,operation.id,job.id,'retried');
  RETURN QUERY SELECT 'retried'::text,operation.id,job.id;
END $$;

-- Scheduled expiry deliberately has no end-user recent-auth context. The
-- approved retention policy is its authority; it still enters the identical
-- blocker, fingerprint, lease, cleanup, storage, and tombstone workflow.
CREATE FUNCTION public.enqueue_due_trash_purges(p_batch_size integer DEFAULT 100)
RETURNS TABLE(queued_count integer,blocked_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate record; queued integer:=0; blocked integer:=0; active_blockers integer;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'invalid Trash purge batch size'; END IF;
  FOR candidate IN
    SELECT operation.* FROM public.trash_operations operation
    WHERE operation.auto_purge_enabled_snapshot AND operation.auto_purge_at<=now()
      AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
      AND NOT EXISTS (SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=operation.id)
    ORDER BY operation.auto_purge_at,operation.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  LOOP
    SELECT count(*)::integer INTO active_blockers
      FROM public.trash_purge_active_blockers(candidate.org_id,candidate.id);
    IF active_blockers>0 THEN
      blocked:=blocked+1;
      UPDATE public.trash_operations SET blocker_count=active_blockers,last_error_code='purge_blocked',updated_at=now()
        WHERE id=candidate.id;
    ELSE
      INSERT INTO public.trash_purge_jobs(org_id,operation_id,source,impact_fingerprint)
        VALUES(candidate.org_id,candidate.id,'retention_schedule',public.trash_purge_impact_fingerprint(candidate.org_id,candidate.id));
      queued:=queued+1;
    END IF;
  END LOOP;
  RETURN QUERY SELECT queued,blocked;
END $$;

-- Restore-blocked roots are still eligible for permanent deletion; the old
-- transition guard predated live purge and is widened only for that edge.
CREATE OR REPLACE FUNCTION public.resource_trash_operation_transition_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.state<>'trashed' THEN RAISE EXCEPTION 'trash operation must begin in trashed state'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.state=OLD.state THEN RETURN NEW; END IF;
  IF OLD.state IN ('restored','purged')
     OR (OLD.state='trashed' AND NEW.state NOT IN ('restore_blocked','restoring','purge_scheduled','purging'))
     OR (OLD.state='restore_blocked' AND NEW.state NOT IN ('trashed','restoring','purge_scheduled','purging'))
     OR (OLD.state='restoring' AND NEW.state NOT IN ('restore_blocked','restored'))
     OR (OLD.state='purge_scheduled' AND NEW.state NOT IN ('trashed','purging'))
     OR (OLD.state='purging' AND NEW.state NOT IN ('purge_failed','purged'))
     OR (OLD.state='purge_failed' AND NEW.state<>'purging') THEN
    RAISE EXCEPTION 'invalid or terminal trash operation transition';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.claim_trash_purge_work(p_batch_size integer DEFAULT 10,p_lease_seconds integer DEFAULT 120)
RETURNS TABLE(job_id uuid,operation_id uuid,org_id uuid,lease_token uuid,database_prepared boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate public.trash_purge_jobs%ROWTYPE; operation public.trash_operations%ROWTYPE;
DECLARE token uuid; active_blockers integer; current_fingerprint text;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 50 OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN
    RAISE EXCEPTION 'invalid Trash purge lease request';
  END IF;
  -- Recover abandoned work. Purging resources remain fenced and inaccessible.
  UPDATE public.trash_purge_jobs job SET state='retryable',lease_token=NULL,lease_expires_at=NULL,
    safe_error_code='stale_lease'
  WHERE job.state='running' AND job.lease_expires_at<=now();
  UPDATE public.trash_operations target_operation SET state='purge_failed',purge_failed_at=now(),
    last_error_code='stale_lease',updated_at=now()
  WHERE target_operation.state='purging' AND EXISTS (
    SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=target_operation.id
      AND job.state='retryable' AND job.safe_error_code='stale_lease'
  );
  UPDATE public.trash_purge_jobs job SET state='blocked',safe_error_code='retry_exhausted'
    WHERE job.state='retryable' AND job.attempt_count>=20;
  FOR candidate IN
    SELECT job.* FROM public.trash_purge_jobs job
    WHERE job.state IN ('queued','retryable','waiting_storage') AND job.attempt_count<20
    ORDER BY job.created_at,job.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  LOOP
    SELECT * INTO operation FROM public.trash_operations WHERE id=candidate.operation_id FOR UPDATE;
    IF operation.id IS NULL OR operation.state IN ('restored','purged') THEN
      UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='not_available' WHERE id=candidate.id;
      CONTINUE;
    END IF;
    IF candidate.database_prepared_at IS NULL THEN
      SELECT count(*)::integer INTO active_blockers
        FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
      IF active_blockers>0 THEN
        UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='purge_blocked' WHERE id=candidate.id;
        UPDATE public.trash_operations SET blocker_count=active_blockers,last_error_code='purge_blocked',updated_at=now() WHERE id=operation.id;
        CONTINUE;
      END IF;
      current_fingerprint:=public.trash_purge_impact_fingerprint(operation.org_id,operation.id);
      IF candidate.source='manual' AND candidate.attempt_count=0
         AND candidate.impact_fingerprint IS DISTINCT FROM current_fingerprint THEN
        UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='stale_impact' WHERE id=candidate.id;
        CONTINUE;
      ELSIF candidate.source='retention_schedule' THEN
        UPDATE public.trash_purge_jobs SET impact_fingerprint=current_fingerprint WHERE id=candidate.id;
      END IF;
      IF operation.state IN ('trashed','restore_blocked','purge_scheduled') THEN
        UPDATE public.trash_operations SET state='purging',purge_started_at=coalesce(purge_started_at,now()),
          purge_failed_at=NULL,last_error_code=NULL,blocker_count=0,updated_at=now() WHERE id=operation.id;
        UPDATE public.resource_trash_memberships target_member SET state='purging',updated_at=now()
          WHERE target_member.org_id=operation.org_id AND target_member.operation_id=operation.id AND target_member.state='active';
        UPDATE public.clients client SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='client' AND member.resource_id=client.id AND client.org_id=member.org_id;
        UPDATE public.matters matter SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='matter' AND member.resource_id=matter.id AND matter.org_id=member.org_id;
        UPDATE public.documents document SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='document' AND member.resource_id=document.id AND document.org_id=member.org_id;
      ELSIF operation.state='purge_failed' THEN
        UPDATE public.trash_operations SET state='purging',purge_failed_at=NULL,last_error_code=NULL,updated_at=now() WHERE id=operation.id;
      END IF;
    ELSIF operation.state='purge_failed' THEN
      UPDATE public.trash_operations SET state='purging',purge_failed_at=NULL,last_error_code=NULL,updated_at=now() WHERE id=operation.id;
    END IF;
    token:=gen_random_uuid();
    UPDATE public.trash_purge_jobs SET state='running',attempt_count=attempt_count+1,
      lease_token=token,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
      started_at=coalesce(started_at,now()),safe_error_code=NULL WHERE id=candidate.id;
    RETURN QUERY SELECT candidate.id,candidate.operation_id,candidate.org_id,token,candidate.database_prepared_at IS NOT NULL;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.prepare_trash_purge_database(p_job_id uuid,p_lease_token uuid)
RETURNS TABLE(code text,storage_deletion_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE job public.trash_purge_jobs%ROWTYPE; operation public.trash_operations%ROWTYPE; deletion_count integer:=0;
DECLARE purge_document_ids uuid[]:='{}'; purge_matter_ids uuid[]:='{}'; purge_client_ids uuid[]:='{}';
DECLARE purge_unique_assets uuid[]:='{}'; purge_intake_ids uuid[]:='{}';
DECLARE active_blockers integer:=0; deleted_run_count integer:=0;
BEGIN
  SELECT * INTO job FROM public.trash_purge_jobs WHERE id=p_job_id FOR UPDATE;
  IF job.id IS NULL OR job.state<>'running' OR job.lease_token IS DISTINCT FROM p_lease_token OR job.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text,0; RETURN;
  END IF;
  IF job.database_prepared_at IS NOT NULL THEN
    SELECT count(*)::integer INTO deletion_count FROM public.trash_purge_storage_deletions WHERE job_id=job.id AND state<>'deleted';
    RETURN QUERY SELECT 'already_prepared'::text,deletion_count; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=job.operation_id FOR UPDATE;
  IF operation.state<>'purging' THEN RETURN QUERY SELECT 'state_mismatch'::text,0; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('trash-purge-dependencies'));
  SELECT count(*)::integer INTO active_blockers
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
  IF active_blockers>0 THEN
    UPDATE public.trash_purge_jobs SET state='blocked',lease_token=NULL,lease_expires_at=NULL,
      safe_error_code='purge_blocked' WHERE id=job.id;
    UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now(),
      last_error_code='purge_blocked',blocker_count=active_blockers,updated_at=now() WHERE id=operation.id;
    RETURN QUERY SELECT 'blocked'::text,0; RETURN;
  END IF;
  INSERT INTO public.trash_purge_execution_fences(transaction_id,job_id) VALUES(txid_current(),job.id)
    ON CONFLICT (transaction_id) DO UPDATE SET job_id=excluded.job_id,created_at=now();

  SELECT coalesce(array_agg(resource_id),'{}'::uuid[]) INTO purge_document_ids FROM public.resource_trash_memberships
    WHERE org_id=operation.org_id AND operation_id=operation.id AND resource_type='document';
  SELECT coalesce(array_agg(resource_id),'{}'::uuid[]) INTO purge_matter_ids FROM public.resource_trash_memberships
    WHERE org_id=operation.org_id AND operation_id=operation.id AND resource_type='matter';
  SELECT coalesce(array_agg(resource_id),'{}'::uuid[]) INTO purge_client_ids FROM public.resource_trash_memberships
    WHERE org_id=operation.org_id AND operation_id=operation.id AND resource_type='client';
  SELECT coalesce(array_agg(DISTINCT assignment.intake_item_id),'{}'::uuid[]) INTO purge_intake_ids
    FROM public.intake_item_assignments assignment
    WHERE assignment.org_id=operation.org_id
      AND assignment.document_id=ANY(purge_document_ids)
      AND NOT EXISTS (SELECT 1 FROM public.intake_item_assignments other_assignment WHERE other_assignment.org_id=assignment.org_id
        AND other_assignment.intake_item_id=assignment.intake_item_id AND NOT (other_assignment.document_id=ANY(purge_document_ids)));
  SELECT coalesce(array_agg(DISTINCT asset.id),'{}'::uuid[]) INTO purge_unique_assets
    FROM public.document_versions version
    JOIN public.file_assets asset ON asset.org_id=version.org_id AND asset.id=version.asset_id
    WHERE version.org_id=operation.org_id AND version.document_id=ANY(purge_document_ids)
      AND NOT EXISTS (SELECT 1 FROM public.document_versions other_version WHERE other_version.org_id=operation.org_id
      AND other_version.asset_id=asset.id AND NOT (other_version.document_id=ANY(purge_document_ids)))
      AND NOT EXISTS (SELECT 1 FROM public.intake_items intake WHERE intake.org_id=operation.org_id AND intake.asset_id=asset.id
        AND NOT (intake.id=ANY(purge_intake_ids)))
      AND NOT EXISTS (SELECT 1 FROM public.source_analysis_runs run
        WHERE run.org_id=operation.org_id AND run.asset_id=asset.id AND (
          NOT EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
            JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id
              AND bound_version.id=binding.document_version_id
            WHERE binding.org_id=operation.org_id AND binding.source_analysis_run_id=run.id
              AND bound_version.document_id=ANY(purge_document_ids))
          OR EXISTS (SELECT 1 FROM public.document_version_analysis_bindings binding
            JOIN public.document_versions bound_version ON bound_version.org_id=binding.org_id
              AND bound_version.id=binding.document_version_id
            WHERE binding.org_id=operation.org_id AND binding.source_analysis_run_id=run.id
              AND NOT (bound_version.document_id=ANY(purge_document_ids)))
        ))
      AND NOT EXISTS (SELECT 1 FROM public.upload_sessions session
        WHERE session.org_id=operation.org_id AND session.asset_id=asset.id
          AND NOT EXISTS (SELECT 1 FROM public.intake_items intake
            WHERE intake.org_id=session.org_id AND intake.upload_session_id=session.id
              AND intake.id=ANY(purge_intake_ids)))
      AND NOT EXISTS (SELECT 1 FROM public.staged_document_backfill_items staged WHERE staged.org_id=operation.org_id
        AND (staged.canonical_asset_id=asset.id OR staged.duplicate_asset_id=asset.id));

  UPDATE public.trash_operations SET
    reason=NULL,
    unique_storage_bytes=(SELECT coalesce(sum(asset.byte_size),0) FROM public.file_assets asset WHERE asset.id=ANY(purge_unique_assets)),
    shared_storage_bytes_retained=(
      SELECT coalesce(sum(shared_asset.byte_size),0) FROM (
        SELECT DISTINCT asset.id,asset.byte_size FROM public.file_assets asset
        JOIN public.document_versions version ON version.org_id=asset.org_id AND version.asset_id=asset.id
        WHERE asset.org_id=operation.org_id AND version.document_id=ANY(purge_document_ids)
          AND NOT (asset.id=ANY(purge_unique_assets))
      ) shared_asset
    ),updated_at=now() WHERE id=operation.id;

  -- Durable external intent precedes every Storage call. Quarantine plus the
  -- existing SHA/version-writer checks prevents a new reference after proof.
  INSERT INTO public.trash_purge_storage_deletions(org_id,job_id,asset_id,bucket_id,object_key)
    SELECT operation.org_id,job.id,asset.id,asset.bucket_id,asset.object_key FROM public.file_assets asset WHERE asset.id=ANY(purge_unique_assets)
    ON CONFLICT (job_id,asset_id) DO NOTHING;
  UPDATE public.file_assets asset SET availability='quarantined',validated_at=NULL,
    storage_delete_attempted_at=now(),storage_delete_failure_code=NULL
    WHERE asset.org_id=operation.org_id AND asset.id=ANY(purge_unique_assets);

  -- Stop projections and remove content-bearing dependants in FK-safe order.
  DELETE FROM public.document_processing_recovery_cases recovery USING public.document_processing_runs run
    WHERE recovery.processing_run_id=run.id AND run.org_id=operation.org_id AND run.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_processing_runs run WHERE run.org_id=operation.org_id AND run.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_effective_metadata metadata WHERE metadata.org_id=operation.org_id AND metadata.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_field_decisions decision WHERE decision.org_id=operation.org_id AND decision.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_field_candidates candidate WHERE candidate.org_id=operation.org_id AND candidate.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_version_analysis_bindings binding WHERE binding.org_id=operation.org_id AND binding.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_relationship_placement_effects effect WHERE effect.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_links link WHERE link.from_doc_id=ANY(purge_document_ids) OR link.to_doc_id=ANY(purge_document_ids);
  DELETE FROM public.supporting_doc_links link WHERE link.document_id=ANY(purge_document_ids);
  DELETE FROM public.document_command_receipts receipt WHERE receipt.org_id=operation.org_id AND receipt.document_id=ANY(purge_document_ids);
  DELETE FROM public.intake_item_assignments assignment WHERE assignment.org_id=operation.org_id AND assignment.document_id=ANY(purge_document_ids);
  UPDATE public.documents document SET current_version_id=NULL,embedding_document_version_id=NULL,embedding=NULL,
    embedding_model=NULL,embedding_version=NULL WHERE document.org_id=operation.org_id AND document.id=ANY(purge_document_ids);
  DELETE FROM public.document_versions version WHERE version.org_id=operation.org_id AND version.document_id=ANY(purge_document_ids);

  DELETE FROM public.source_field_candidates candidate WHERE candidate.org_id=operation.org_id AND candidate.asset_id=ANY(purge_unique_assets);
  DELETE FROM public.source_analysis_attempts attempt USING public.source_analysis_runs run
    WHERE attempt.org_id=operation.org_id AND attempt.source_analysis_run_id=run.id AND run.org_id=operation.org_id AND run.asset_id=ANY(purge_unique_assets);
  -- Supersession is immutable even during purge. Delete the oldest remaining
  -- provenance leaf first so the self-RESTRICT FK is satisfied without ever
  -- rewriting terminal run state.
  LOOP
    DELETE FROM public.source_analysis_runs run
    WHERE run.org_id=operation.org_id AND run.asset_id=ANY(purge_unique_assets)
      AND NOT EXISTS (
        SELECT 1 FROM public.source_analysis_runs predecessor
        WHERE predecessor.org_id=run.org_id AND predecessor.superseded_by_run_id=run.id
          AND predecessor.asset_id=ANY(purge_unique_assets)
      );
    GET DIAGNOSTICS deleted_run_count=ROW_COUNT;
    EXIT WHEN deleted_run_count=0;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.source_analysis_runs run
    WHERE run.org_id=operation.org_id AND run.asset_id=ANY(purge_unique_assets)) THEN
    RAISE EXCEPTION 'Trash purge provenance dependency cycle';
  END IF;
  DELETE FROM public.document_upload_command_receipts receipt USING public.upload_sessions session
    WHERE receipt.upload_session_id=session.id AND session.org_id=operation.org_id
      AND EXISTS (SELECT 1 FROM public.intake_items item WHERE item.id=ANY(purge_intake_ids) AND item.upload_session_id=session.id);
  DELETE FROM public.storage_reservations reservation USING public.upload_sessions session
    WHERE reservation.org_id=operation.org_id AND reservation.upload_session_id=session.id
      AND EXISTS (SELECT 1 FROM public.intake_items item WHERE item.id=ANY(purge_intake_ids) AND item.upload_session_id=session.id);
  DELETE FROM public.intake_items item WHERE item.org_id=operation.org_id AND item.id=ANY(purge_intake_ids);
  DELETE FROM public.upload_sessions session WHERE session.org_id=operation.org_id AND EXISTS (
    SELECT 1 WHERE session.asset_id=ANY(purge_unique_assets)
  ) AND NOT EXISTS (SELECT 1 FROM public.intake_items item WHERE item.org_id=session.org_id AND item.upload_session_id=session.id);

  DELETE FROM public.case_notes note WHERE note.org_id=operation.org_id AND (
    note.matter_id=ANY(purge_matter_ids) OR note.document_id=ANY(purge_document_ids));
  DELETE FROM public.deadlines deadline WHERE deadline.matter_id=ANY(purge_matter_ids)
    OR deadline.document_id=ANY(purge_document_ids);
  DELETE FROM public.wiki_sections wiki WHERE wiki.matter_id=ANY(purge_matter_ids);
  DELETE FROM public.ai_usage_logs usage WHERE usage.org_id=operation.org_id AND usage.document_id=ANY(purge_document_ids);
  DELETE FROM public.notifications notification WHERE notification.org_id=operation.org_id AND (
    (notification.entity_type='client' AND notification.entity_id=ANY(purge_client_ids))
    OR (notification.entity_type='matter' AND notification.entity_id=ANY(purge_matter_ids))
    OR (notification.entity_type='document' AND notification.entity_id=ANY(purge_document_ids)));
  UPDATE public.activity_logs activity SET action='resource_purged',description=NULL,metadata='{}',
    is_reversible=false,reversed_by=NULL,reversed_at=NULL WHERE activity.org_id=operation.org_id AND (
    (activity.entity_type='client' AND activity.entity_id=ANY(purge_client_ids))
    OR (activity.entity_type='matter' AND activity.entity_id=ANY(purge_matter_ids))
    OR (activity.entity_type='document' AND activity.entity_id=ANY(purge_document_ids)));
  UPDATE public.staged_documents staged SET suggested_client_id=NULL WHERE staged.org_id=operation.org_id AND staged.suggested_client_id=ANY(purge_client_ids);
  UPDATE public.staged_documents staged SET suggested_matter_id=NULL,intake_matter_id=NULL WHERE staged.org_id=operation.org_id
    AND (staged.suggested_matter_id=ANY(purge_matter_ids) OR staged.intake_matter_id=ANY(purge_matter_ids));
  UPDATE public.documents other_document SET copied_from_document_id=NULL WHERE other_document.org_id=operation.org_id
    AND other_document.copied_from_document_id=ANY(purge_document_ids)
    AND NOT (other_document.id=ANY(purge_document_ids));

  -- Resource shells are inaccessible and contain only opaque lineage plus safe
  -- lifecycle markers while external deletion is reconciled.
  UPDATE public.documents document SET doc_type=NULL,reference_number=NULL,doc_date=NULL,direction=NULL,issued_by=NULL,
    financial_year=NULL,summary=NULL,raw_metadata='{}',ai_prompt_version=NULL,storage_path='purged',file_hash_sha256=NULL,
    content_hash=NULL,document_class=NULL,document_category=NULL,confidence_scores=NULL,review_reason=NULL,
    effective_filename=NULL,display_title=NULL,trashed_reason=NULL
    WHERE document.org_id=operation.org_id AND document.id=ANY(purge_document_ids);
  UPDATE public.matters matter SET title='Permanently deleted',financial_year=NULL,description=NULL,matter_code=NULL
    WHERE matter.org_id=operation.org_id AND matter.id=ANY(purge_matter_ids);
  UPDATE public.clients client SET name='Permanently deleted',gstin=NULL,pan=NULL,company_name=NULL,contact_info='{}'
    WHERE client.org_id=operation.org_id AND client.id=ANY(purge_client_ids);

  UPDATE public.trash_purge_jobs SET database_prepared_at=now(),state='running' WHERE id=job.id;
  DELETE FROM public.trash_purge_execution_fences WHERE transaction_id=txid_current() AND job_id=job.id;
  SELECT count(*)::integer INTO deletion_count FROM public.trash_purge_storage_deletions WHERE job_id=job.id AND state<>'deleted';
  RETURN QUERY SELECT 'prepared'::text,deletion_count;
END $$;

CREATE FUNCTION public.claim_trash_purge_storage_deletions(
  p_job_id uuid,p_job_lease_token uuid,p_batch_size integer DEFAULT 25,p_lease_seconds integer DEFAULT 120
) RETURNS TABLE(deletion_id uuid,bucket_id text,object_key text,lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE job public.trash_purge_jobs%ROWTYPE;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 100 OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN
    RAISE EXCEPTION 'invalid Trash storage lease request';
  END IF;
  SELECT * INTO job FROM public.trash_purge_jobs WHERE id=p_job_id FOR UPDATE;
  IF job.id IS NULL OR job.state<>'running' OR job.lease_token IS DISTINCT FROM p_job_lease_token
     OR job.lease_expires_at<=now() OR job.database_prepared_at IS NULL THEN RETURN; END IF;
  UPDATE public.trash_purge_storage_deletions deletion SET state='pending',lease_token=NULL,lease_expires_at=NULL,
    safe_error_code='stale_lease' WHERE deletion.job_id=job.id AND deletion.state='leased' AND deletion.lease_expires_at<=now();
  RETURN QUERY WITH candidates AS (
    SELECT deletion.id FROM public.trash_purge_storage_deletions deletion
    WHERE deletion.job_id=job.id AND deletion.state='pending' AND deletion.attempt_count<20
    ORDER BY deletion.created_at,deletion.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  ), leased AS (
    UPDATE public.trash_purge_storage_deletions deletion SET state='leased',attempt_count=attempt_count+1,
      lease_token=gen_random_uuid(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds),safe_error_code=NULL
    FROM candidates WHERE deletion.id=candidates.id
    RETURNING deletion.id,deletion.bucket_id,deletion.object_key,deletion.lease_token
  ) SELECT leased.id,leased.bucket_id,leased.object_key,leased.lease_token FROM leased;
END $$;

CREATE FUNCTION public.finish_trash_purge_storage_deletion(
  p_deletion_id uuid,p_lease_token uuid,p_outcome text
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE deletion public.trash_purge_storage_deletions%ROWTYPE;
BEGIN
  IF p_outcome NOT IN ('deleted','failed') THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT * INTO deletion FROM public.trash_purge_storage_deletions WHERE id=p_deletion_id FOR UPDATE;
  IF deletion.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
  IF deletion.state='deleted' THEN RETURN QUERY SELECT 'already_deleted'::text; RETURN; END IF;
  IF deletion.state<>'leased' OR deletion.lease_token IS DISTINCT FROM p_lease_token OR deletion.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text; RETURN;
  END IF;
  IF p_outcome='failed' THEN
    UPDATE public.trash_purge_storage_deletions SET state='pending',lease_token=NULL,lease_expires_at=NULL,
      safe_error_code='storage_delete_failed' WHERE id=deletion.id;
    RETURN QUERY SELECT 'failed'::text; RETURN;
  END IF;
  -- Storage DELETE and explicit not-found both reconcile to this idempotent
  -- completion. Scrub the private locator immediately after confirmation.
  UPDATE public.file_assets SET storage_deleted_at=coalesce(storage_deleted_at,now()),storage_delete_attempted_at=now(),
    storage_deletion_lease_token=NULL,storage_deletion_lease_expires_at=NULL,storage_delete_failure_code=NULL
    WHERE org_id=deletion.org_id AND id=deletion.asset_id;
  UPDATE public.trash_purge_storage_deletions SET state='deleted',bucket_id=NULL,object_key=NULL,
    lease_token=NULL,lease_expires_at=NULL,safe_error_code=NULL,deleted_at=now() WHERE id=deletion.id;
  RETURN QUERY SELECT 'deleted'::text;
END $$;

CREATE OR REPLACE FUNCTION public.finish_trash_purge_attempt(p_job_id uuid,p_lease_token uuid)
RETURNS TABLE(code text,operation_id uuid,pending_storage_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE job public.trash_purge_jobs%ROWTYPE; operation public.trash_operations%ROWTYPE;
DECLARE pending integer; now_at timestamptz:=now(); expected_assets integer; deleted_assets integer; active_blockers integer:=0;
BEGIN
  SELECT * INTO job FROM public.trash_purge_jobs WHERE id=p_job_id FOR UPDATE;
  IF job.id IS NULL OR job.state<>'running' OR job.lease_token IS DISTINCT FROM p_lease_token OR job.lease_expires_at<=now() THEN
    RETURN QUERY SELECT 'stale_lease'::text,NULL::uuid,0; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=job.operation_id FOR UPDATE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(operation.org_id::text),pg_catalog.hashtext('trash-purge-dependencies'));
  SELECT count(*)::integer INTO active_blockers
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
  IF active_blockers>0 THEN
    UPDATE public.trash_purge_jobs SET state='blocked',lease_token=NULL,lease_expires_at=NULL,
      safe_error_code='purge_blocked' WHERE id=job.id;
    UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now_at,
      last_error_code='purge_blocked',blocker_count=active_blockers,updated_at=now_at WHERE id=operation.id;
    RETURN QUERY SELECT 'blocked'::text,operation.id,0; RETURN;
  END IF;
  SELECT count(*)::integer INTO pending FROM public.trash_purge_storage_deletions deletion
    WHERE deletion.job_id=job.id AND deletion.state<>'deleted';
  IF pending>0 THEN
    UPDATE public.trash_purge_jobs SET state='retryable',lease_token=NULL,lease_expires_at=NULL,
      safe_error_code='storage_delete_failed' WHERE id=job.id;
    UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now_at,last_error_code='storage_delete_failed',updated_at=now_at
      WHERE id=operation.id AND state='purging';
    RETURN QUERY SELECT 'retryable'::text,operation.id,pending; RETURN;
  END IF;
  IF job.database_prepared_at IS NULL OR operation.state<>'purging' THEN
    RETURN QUERY SELECT 'state_mismatch'::text,operation.id,0; RETURN;
  END IF;
  INSERT INTO public.trash_purge_execution_fences(transaction_id,job_id) VALUES(txid_current(),job.id)
    ON CONFLICT (transaction_id) DO UPDATE SET job_id=excluded.job_id,created_at=now();

  -- Final transactional proof: every externally deleted asset must still have
  -- zero surviving references. Quarantine fenced production writers while the
  -- durable intent was outstanding; direct FK/DML bypass therefore fails.
  IF EXISTS (
    SELECT 1 FROM public.trash_purge_storage_deletions deletion
    WHERE deletion.job_id=job.id AND deletion.asset_id IS NOT NULL AND (
      EXISTS (SELECT 1 FROM public.document_versions version WHERE version.org_id=deletion.org_id AND version.asset_id=deletion.asset_id)
      OR EXISTS (SELECT 1 FROM public.intake_items intake WHERE intake.org_id=deletion.org_id AND intake.asset_id=deletion.asset_id)
      OR EXISTS (SELECT 1 FROM public.source_analysis_runs run WHERE run.org_id=deletion.org_id AND run.asset_id=deletion.asset_id)
      OR EXISTS (SELECT 1 FROM public.source_field_candidates candidate WHERE candidate.org_id=deletion.org_id AND candidate.asset_id=deletion.asset_id)
      OR EXISTS (SELECT 1 FROM public.upload_sessions session WHERE session.org_id=deletion.org_id AND session.asset_id=deletion.asset_id)
      OR EXISTS (SELECT 1 FROM public.staged_document_backfill_items staged WHERE staged.org_id=deletion.org_id
        AND (staged.canonical_asset_id=deletion.asset_id OR staged.duplicate_asset_id=deletion.asset_id))
    )
  ) THEN
    UPDATE public.trash_purge_jobs SET state='retryable',lease_token=NULL,lease_expires_at=NULL,
      safe_error_code='asset_reference_changed' WHERE id=job.id;
    UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now_at,last_error_code='asset_reference_changed',updated_at=now_at
      WHERE id=operation.id;
    RETURN QUERY SELECT 'retryable'::text,operation.id,0; RETURN;
  END IF;
  SELECT count(*)::integer INTO expected_assets FROM public.trash_purge_storage_deletions WHERE job_id=job.id AND asset_id IS NOT NULL;
  DELETE FROM public.file_assets asset USING public.trash_purge_storage_deletions deletion
    WHERE deletion.job_id=job.id AND deletion.asset_id=asset.id AND asset.org_id=deletion.org_id AND deletion.state='deleted';
  GET DIAGNOSTICS deleted_assets=ROW_COUNT;
  IF deleted_assets<>expected_assets THEN RAISE EXCEPTION 'Trash purge asset finalization mismatch'; END IF;

  INSERT INTO public.trash_purge_tombstones(
    org_id,operation_id,job_id,resource_type,former_resource_id,source,actor_user_id,verification_code,purged_at
  ) SELECT member.org_id,member.operation_id,job.id,member.resource_type,member.resource_id,job.source,job.confirmed_by,
      CASE WHEN expected_assets>0 THEN 'database_and_storage_verified' ELSE 'database_only_verified' END,now_at
    FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
    ON CONFLICT ON CONSTRAINT trash_purge_tombstones_operation_resource_unique DO NOTHING;
  UPDATE public.clients client SET record_state='purged',active_trash_membership_id=NULL
    FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
      AND member.resource_type='client' AND member.resource_id=client.id AND client.org_id=member.org_id;
  UPDATE public.matters matter SET record_state='purged',active_trash_membership_id=NULL
    FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
      AND member.resource_type='matter' AND member.resource_id=matter.id AND matter.org_id=member.org_id;
  UPDATE public.documents document SET record_state='purged',active_trash_membership_id=NULL,content_availability='purged',
    lifecycle_revision=lifecycle_revision+1,lifecycle_updated_at=now_at
    FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
      AND member.resource_type='document' AND member.resource_id=document.id AND document.org_id=member.org_id;
  UPDATE public.resource_trash_memberships target_member SET state='purged',purged_at=now_at,updated_at=now_at
    WHERE target_member.org_id=operation.org_id AND target_member.operation_id=operation.id AND target_member.state='purging';
  UPDATE public.trash_operations SET state='purged',purged_at=now_at,purge_failed_at=NULL,last_error_code=NULL,
    updated_at=now_at
    WHERE id=operation.id;
  UPDATE public.trash_purge_jobs SET state='completed',lease_token=NULL,lease_expires_at=NULL,
    safe_error_code=NULL,completed_at=now_at WHERE id=job.id;
  DELETE FROM public.trash_purge_execution_fences WHERE transaction_id=txid_current() AND job_id=job.id;
  RETURN QUERY SELECT 'purged'::text,operation.id,0;
END $$;

REVOKE ALL ON FUNCTION
  public.register_trash_purge_blocker(uuid,public.trash_resource_type,uuid,public.trash_purge_blocker_kind,uuid,boolean),
  public.trash_purge_active_blockers(uuid,uuid),
  public.trash_purge_impact_fingerprint(uuid,uuid),public.get_trash_purge_impact(uuid),
  public.confirm_trash_purge(uuid,text,text,text),public.retry_trash_purge(uuid,text,text),public.enqueue_due_trash_purges(integer),
  public.claim_trash_purge_work(integer,integer),public.prepare_trash_purge_database(uuid,uuid),
  public.claim_trash_purge_storage_deletions(uuid,uuid,integer,integer),
  public.finish_trash_purge_storage_deletion(uuid,uuid,text),public.finish_trash_purge_attempt(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_trash_purge_impact(uuid),public.confirm_trash_purge(uuid,text,text,text),
  public.retry_trash_purge(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.register_trash_purge_blocker(uuid,public.trash_resource_type,uuid,public.trash_purge_blocker_kind,uuid,boolean),
  public.enqueue_due_trash_purges(integer),public.claim_trash_purge_work(integer,integer),
  public.prepare_trash_purge_database(uuid,uuid),public.claim_trash_purge_storage_deletions(uuid,uuid,integer,integer),
  public.finish_trash_purge_storage_deletion(uuid,uuid,text),public.finish_trash_purge_attempt(uuid,uuid)
  TO service_role;

COMMENT ON FUNCTION public.get_trash_purge_impact(uuid) IS
  'Authenticated tenant-scoped, content-safe permanent-delete impact and operational status for one exact root Trash operation.';
COMMENT ON FUNCTION public.confirm_trash_purge(uuid,text,text,text) IS
  'Owner/Admin manual permanent-delete confirmation bound to recent JWT authentication, exact current root phrase, impact fingerprint, and actor idempotency key.';
COMMENT ON FUNCTION public.enqueue_due_trash_purges(integer) IS
  'Service-only retention scheduler entering the same blocker/fingerprint/durable workflow as manual permanent deletion; recent user authentication is not applicable to policy execution.';
COMMENT ON TABLE public.trash_purge_tombstones IS
  'Content-free terminal proof containing only tenant, opaque former subject, execution source, actor when manual, verification code, and time.';

COMMIT;
