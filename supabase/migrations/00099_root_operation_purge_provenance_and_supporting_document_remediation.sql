-- Remediate two permanent-delete boundary defects without widening any
-- ordinary provenance or legacy supporting-document mutation authority.
BEGIN;

-- Terminal provenance remains immutable in every ordinary write path. The
-- sole exception is removing a terminal run's supersession edge while the
-- exact asset is owned by the current transaction of a live purge lease. This
-- lets the worker de-link an otherwise terminal chain before deleting its
-- runs, while a caller cannot manufacture the authority from a GUC or a stale
-- job receipt.
CREATE OR REPLACE FUNCTION public.source_analysis_provenance_run_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE terminal boolean;
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.org_id IS DISTINCT FROM OLD.org_id
     OR NEW.asset_id IS DISTINCT FROM OLD.asset_id
     OR NEW.request_key IS DISTINCT FROM OLD.request_key
     OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
     OR NEW.analysis_kind IS DISTINCT FROM OLD.analysis_kind
     OR NEW.page_content_version IS DISTINCT FROM OLD.page_content_version
     OR NEW.provider IS DISTINCT FROM OLD.provider
     OR NEW.model_identifier IS DISTINCT FROM OLD.model_identifier
     OR NEW.model_config_version IS DISTINCT FROM OLD.model_config_version
     OR NEW.prompt_version IS DISTINCT FROM OLD.prompt_version
     OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.catalogue_version IS DISTINCT FROM OLD.catalogue_version
     OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'source analysis provenance identity is immutable';
  END IF;

  terminal := CASE
    WHEN OLD.analysis_kind = 'ai_extraction'
      THEN OLD.analysis_state IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required')
    ELSE OLD.state IN ('succeeded', 'failed')
  END;
  IF terminal THEN
    IF OLD.superseded_by_run_id IS NOT NULL
       AND NEW.superseded_by_run_id IS NULL
       AND (to_jsonb(NEW) - 'superseded_by_run_id')
         IS NOT DISTINCT FROM (to_jsonb(OLD) - 'superseded_by_run_id')
       AND public.trash_purge_current_job_owns_asset(OLD.org_id, OLD.asset_id) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'terminal source analysis runs are immutable';
  END IF;

  IF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'queued'
     AND NEW.analysis_state NOT IN ('queued', 'running') THEN
    RAISE EXCEPTION 'source analysis run must be claimed before completion';
  ELSIF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'running'
     AND NEW.analysis_state = 'queued' THEN
    IF OLD.lease_expires_at IS NULL OR OLD.lease_expires_at > now()
       OR NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.failed_at IS NOT NULL
       OR NEW.lease_token IS NOT NULL OR NEW.lease_expires_at IS NOT NULL THEN
      RAISE EXCEPTION 'source analysis run may be replayed only after its lease expires';
    END IF;
  ELSIF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'running'
     AND NEW.analysis_state NOT IN ('running', 'validated', 'invalid_model_output', 'provider_failed', 'review_required') THEN
    RAISE EXCEPTION 'invalid source analysis run transition';
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'queued' AND NEW.state NOT IN ('queued', 'running') THEN
    RAISE EXCEPTION 'source analysis run must be claimed before completion';
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'running' AND NEW.state = 'queued' THEN
    IF OLD.lease_expires_at IS NULL OR OLD.lease_expires_at > now()
       OR NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.failed_at IS NOT NULL
       OR NEW.lease_token IS NOT NULL OR NEW.lease_expires_at IS NOT NULL THEN
      RAISE EXCEPTION 'source analysis run may be replayed only after its lease expires';
    END IF;
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'running'
     AND NEW.state NOT IN ('running', 'succeeded', 'failed') THEN
    RAISE EXCEPTION 'invalid source analysis run transition';
  END IF;

  IF OLD.analysis_kind = 'ai_extraction'
     AND OLD.analysis_state = 'running'
     AND NEW.analysis_state IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required') THEN
    IF OLD.lease_token IS NULL OR OLD.lease_expires_at IS NULL OR OLD.lease_expires_at <= now() THEN
      RAISE EXCEPTION 'source analysis terminal transition requires an active lease';
    END IF;
    IF NEW.lease_token IS DISTINCT FROM OLD.lease_token
       OR NEW.lease_expires_at IS DISTINCT FROM OLD.lease_expires_at THEN
      RAISE EXCEPTION 'source analysis terminal transition must retain its active lease fence';
    END IF;
  END IF;

  IF OLD.provider_request_id IS NOT NULL AND NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id THEN
    RAISE EXCEPTION 'source analysis provider request identity is immutable';
  END IF;
  IF OLD.provider_operation_id IS NOT NULL AND NEW.provider_operation_id IS DISTINCT FROM OLD.provider_operation_id THEN
    RAISE EXCEPTION 'source analysis provider operation identity is immutable';
  END IF;
  IF OLD.superseded_by_run_id IS NOT NULL AND NEW.superseded_by_run_id IS DISTINCT FROM OLD.superseded_by_run_id THEN
    RAISE EXCEPTION 'source analysis supersession is immutable';
  END IF;
  RETURN NEW;
END;
$$;

-- The blocker store has no supported physical-delete command. Keep both its
-- deny trigger and its access posture independent from the generic root guard
-- so a direct service-role delete cannot make a pending root operation appear
-- purgeable. The RESTRICT actions also close the adjacent parent-delete path.
CREATE OR REPLACE FUNCTION public.governed_supporting_document_prevent_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'supporting documents remain governed permanent-delete blockers';
END;
$$;

DROP TRIGGER IF EXISTS supporting_documents_no_hard_delete ON public.supporting_documents;
CREATE TRIGGER supporting_documents_no_hard_delete
  BEFORE DELETE ON public.supporting_documents
  FOR EACH ROW EXECUTE FUNCTION public.governed_supporting_document_prevent_delete();

ALTER TABLE public.supporting_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supporting_documents FORCE ROW LEVEL SECURITY;
ALTER TABLE public.supporting_documents
  DROP CONSTRAINT IF EXISTS supporting_documents_matter_id_fkey,
  ADD CONSTRAINT supporting_documents_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT;
ALTER TABLE public.supporting_doc_links
  DROP CONSTRAINT IF EXISTS supporting_doc_links_supporting_doc_id_fkey,
  ADD CONSTRAINT supporting_doc_links_supporting_doc_id_fkey
    FOREIGN KEY (supporting_doc_id) REFERENCES public.supporting_documents(id) ON DELETE RESTRICT;

REVOKE DELETE, TRUNCATE ON TABLE public.supporting_documents
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.governed_supporting_document_prevent_delete()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.source_analysis_provenance_run_transition_guard() IS
  'Terminal source-analysis runs are immutable except for a supersession unlink performed in the exact transaction of a live, owned Trash purge asset lease.';
COMMENT ON FUNCTION public.governed_supporting_document_prevent_delete() IS
  'Fail-closed supporting-document blocker delete guard; no direct caller, including service_role, may remove a blocker outside governed retention remediation.';

COMMIT;
