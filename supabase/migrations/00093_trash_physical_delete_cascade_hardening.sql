-- Close every remaining physical-delete escape hatch beneath the governed
-- Client -> Matter -> Document hierarchy. Root records deliberately remain
-- opaque purged shells; dependency rows may be removed only by a leased,
-- transaction-fenced permanent-delete attempt.
BEGIN;

-- The original schema predated the Trash lifecycle and encoded ordinary
-- deletion as cascades (and a few SET NULL actions). Replacing each action
-- with RESTRICT means a parent cannot silently erase or mutate its evidence.
-- The governed worker already deletes these dependants in explicit order.
ALTER TABLE public.matters
  DROP CONSTRAINT IF EXISTS matters_client_id_fkey,
  ADD CONSTRAINT matters_client_id_fkey
    FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS matters_org_id_fkey,
  ADD CONSTRAINT matters_org_id_fkey
    FOREIGN KEY (org_id) REFERENCES public.organisations(id) ON DELETE RESTRICT;

ALTER TABLE public.documents
  DROP CONSTRAINT IF EXISTS documents_matter_id_fkey,
  ADD CONSTRAINT documents_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS documents_org_id_fkey,
  ADD CONSTRAINT documents_org_id_fkey
    FOREIGN KEY (org_id) REFERENCES public.organisations(id) ON DELETE RESTRICT;

ALTER TABLE public.clients
  DROP CONSTRAINT IF EXISTS clients_org_id_fkey,
  ADD CONSTRAINT clients_org_id_fkey
    FOREIGN KEY (org_id) REFERENCES public.organisations(id) ON DELETE RESTRICT;

ALTER TABLE public.document_links
  DROP CONSTRAINT IF EXISTS document_links_from_doc_id_fkey,
  ADD CONSTRAINT document_links_from_doc_id_fkey
    FOREIGN KEY (from_doc_id) REFERENCES public.documents(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS document_links_to_doc_id_fkey,
  ADD CONSTRAINT document_links_to_doc_id_fkey
    FOREIGN KEY (to_doc_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE public.supporting_documents
  DROP CONSTRAINT IF EXISTS supporting_documents_matter_id_fkey,
  ADD CONSTRAINT supporting_documents_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT;

ALTER TABLE public.supporting_doc_links
  DROP CONSTRAINT IF EXISTS supporting_doc_links_supporting_doc_id_fkey,
  ADD CONSTRAINT supporting_doc_links_supporting_doc_id_fkey
    FOREIGN KEY (supporting_doc_id) REFERENCES public.supporting_documents(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS supporting_doc_links_document_id_fkey,
  ADD CONSTRAINT supporting_doc_links_document_id_fkey
    FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE public.deadlines
  DROP CONSTRAINT IF EXISTS deadlines_matter_id_fkey,
  ADD CONSTRAINT deadlines_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS deadlines_document_id_fkey,
  ADD CONSTRAINT deadlines_document_id_fkey
    FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE public.case_notes
  DROP CONSTRAINT IF EXISTS case_notes_matter_id_fkey,
  ADD CONSTRAINT case_notes_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS case_notes_document_id_fkey,
  ADD CONSTRAINT case_notes_document_id_fkey
    FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE public.wiki_sections
  DROP CONSTRAINT IF EXISTS wiki_sections_matter_id_fkey,
  ADD CONSTRAINT wiki_sections_matter_id_fkey
    FOREIGN KEY (matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT;

ALTER TABLE public.wiki_section_versions
  DROP CONSTRAINT IF EXISTS wiki_section_versions_wiki_section_id_fkey,
  ADD CONSTRAINT wiki_section_versions_wiki_section_id_fkey
    FOREIGN KEY (wiki_section_id) REFERENCES public.wiki_sections(id) ON DELETE RESTRICT;

ALTER TABLE public.ai_usage_logs
  DROP CONSTRAINT IF EXISTS ai_usage_logs_document_id_fkey,
  ADD CONSTRAINT ai_usage_logs_document_id_fkey
    FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE public.staged_documents
  DROP CONSTRAINT IF EXISTS staged_documents_intake_matter_id_fkey,
  ADD CONSTRAINT staged_documents_intake_matter_id_fkey
    FOREIGN KEY (intake_matter_id) REFERENCES public.matters(id) ON DELETE RESTRICT;

ALTER TABLE public.document_relationship_placement_effects
  DROP CONSTRAINT IF EXISTS document_relationship_placement_effects_document_id_fkey,
  ADD CONSTRAINT document_relationship_placement_effects_document_id_fkey
    FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT,
  DROP CONSTRAINT IF EXISTS document_relationship_placement_effect_document_version_id_fkey,
  ADD CONSTRAINT document_relationship_effect_version_fkey
    FOREIGN KEY (document_version_id) REFERENCES public.document_versions(id) ON DELETE RESTRICT;

-- A fence row is created only inside prepare/finish after the service-only
-- worker has locked the job, checked the lease, and rechecked blockers. It is
-- transaction-local by construction: a stale/lost lease cannot satisfy this
-- guard in a later transaction.
CREATE FUNCTION public.trash_purge_current_job_owns_resource(
  p_org_id uuid, p_resource_type public.trash_resource_type, p_resource_id uuid
) RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trash_purge_execution_fences fence
    JOIN public.trash_purge_jobs job ON job.id=fence.job_id
    JOIN public.resource_trash_memberships member
      ON member.org_id=job.org_id AND member.operation_id=job.operation_id
     AND member.resource_type=p_resource_type AND member.resource_id=p_resource_id
    WHERE fence.transaction_id=txid_current() AND job.org_id=p_org_id
      AND job.state='running'::public.trash_purge_job_state
      AND job.lease_token IS NOT NULL AND job.lease_expires_at>now()
  )
$$;

CREATE FUNCTION public.trash_purge_current_job_owns_asset(p_org_id uuid, p_asset_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trash_purge_execution_fences fence
    JOIN public.trash_purge_jobs job ON job.id=fence.job_id
    JOIN public.trash_purge_storage_deletions deletion ON deletion.job_id=job.id
    WHERE fence.transaction_id=txid_current() AND job.org_id=p_org_id AND deletion.asset_id=p_asset_id
      AND job.state='running'::public.trash_purge_job_state
      AND job.lease_token IS NOT NULL AND job.lease_expires_at>now()
  )
$$;

CREATE OR REPLACE FUNCTION public.governed_trash_purge_dependency_delete_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  CASE TG_TABLE_NAME
    WHEN 'document_links' THEN IF EXISTS (SELECT 1 FROM public.documents d WHERE d.id IN (OLD.from_doc_id,OLD.to_doc_id) AND public.trash_purge_current_job_owns_resource(d.org_id,'document',d.id)) THEN RETURN OLD; END IF;
    WHEN 'supporting_doc_links','document_relationship_placement_effects' THEN IF EXISTS (SELECT 1 FROM public.documents d WHERE d.id=OLD.document_id AND public.trash_purge_current_job_owns_resource(d.org_id,'document',d.id)) THEN RETURN OLD; END IF;
    WHEN 'deadlines' THEN IF EXISTS (SELECT 1 FROM public.matters m WHERE m.id=OLD.matter_id AND public.trash_purge_current_job_owns_resource(m.org_id,'matter',m.id)) OR EXISTS (SELECT 1 FROM public.documents d WHERE d.id=OLD.document_id AND public.trash_purge_current_job_owns_resource(d.org_id,'document',d.id)) THEN RETURN OLD; END IF;
    WHEN 'case_notes' THEN IF public.trash_purge_current_job_owns_resource(OLD.org_id,'matter',OLD.matter_id) OR (OLD.document_id IS NOT NULL AND public.trash_purge_current_job_owns_resource(OLD.org_id,'document',OLD.document_id)) THEN RETURN OLD; END IF;
    WHEN 'wiki_sections' THEN IF EXISTS (SELECT 1 FROM public.matters m WHERE m.id=OLD.matter_id AND public.trash_purge_current_job_owns_resource(m.org_id,'matter',m.id)) THEN RETURN OLD; END IF;
    WHEN 'wiki_section_versions' THEN IF EXISTS (SELECT 1 FROM public.wiki_sections w JOIN public.matters m ON m.id=w.matter_id WHERE w.id=OLD.wiki_section_id AND public.trash_purge_current_job_owns_resource(m.org_id,'matter',m.id)) THEN RETURN OLD; END IF;
    WHEN 'ai_usage_logs','document_processing_runs','document_command_receipts','intake_item_assignments' THEN IF OLD.document_id IS NOT NULL AND public.trash_purge_current_job_owns_resource(OLD.org_id,'document',OLD.document_id) THEN RETURN OLD; END IF;
    WHEN 'document_processing_recovery_cases' THEN IF EXISTS (SELECT 1 FROM public.document_processing_runs r WHERE r.id=OLD.processing_run_id AND public.trash_purge_current_job_owns_resource(r.org_id,'document',r.document_id)) THEN RETURN OLD; END IF;
    WHEN 'intake_items','upload_sessions' THEN IF public.trash_purge_current_job_owns_asset(OLD.org_id,OLD.asset_id) THEN RETURN OLD; END IF;
    WHEN 'document_upload_command_receipts' THEN IF EXISTS (SELECT 1 FROM public.upload_sessions s WHERE s.id=OLD.upload_session_id AND public.trash_purge_current_job_owns_asset(s.org_id,s.asset_id)) THEN RETURN OLD; END IF;
  END CASE;

  RAISE EXCEPTION 'governed hierarchy dependants require an active fenced Trash purge attempt';
END;
$$;

-- Wiki versions used to be deleted by FK cascade. The worker still removes
-- them atomically, but explicitly and only after the same valid fence check.
CREATE OR REPLACE FUNCTION public.governed_wiki_section_purge_cleanup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.matters m WHERE m.id=OLD.matter_id
    AND public.trash_purge_current_job_owns_resource(m.org_id,'matter',m.id)) THEN
    RAISE EXCEPTION 'governed hierarchy dependants require an active fenced Trash purge attempt';
  END IF;
  DELETE FROM public.wiki_section_versions WHERE wiki_section_id = OLD.id;
  RETURN OLD;
END;
$$;

CREATE TRIGGER aa_wiki_sections_governed_purge_cleanup
  BEFORE DELETE ON public.wiki_sections
  FOR EACH ROW EXECUTE FUNCTION public.governed_wiki_section_purge_cleanup();

CREATE TRIGGER zz_document_links_governed_purge_delete
  BEFORE DELETE ON public.document_links
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_supporting_doc_links_governed_purge_delete
  BEFORE DELETE ON public.supporting_doc_links
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_deadlines_governed_purge_delete
  BEFORE DELETE ON public.deadlines
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_case_notes_governed_purge_delete
  BEFORE DELETE ON public.case_notes
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_wiki_sections_governed_purge_delete
  BEFORE DELETE ON public.wiki_sections
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_wiki_section_versions_governed_purge_delete
  BEFORE DELETE ON public.wiki_section_versions
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_ai_usage_logs_governed_purge_delete
  BEFORE DELETE ON public.ai_usage_logs
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_document_relationship_effects_governed_purge_delete
  BEFORE DELETE ON public.document_relationship_placement_effects
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_document_processing_runs_governed_purge_delete
  BEFORE DELETE ON public.document_processing_runs
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_document_processing_recovery_governed_purge_delete
  BEFORE DELETE ON public.document_processing_recovery_cases
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_document_command_receipts_governed_purge_delete
  BEFORE DELETE ON public.document_command_receipts
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_intake_item_assignments_governed_purge_delete
  BEFORE DELETE ON public.intake_item_assignments
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_intake_items_governed_purge_delete
  BEFORE DELETE ON public.intake_items
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_upload_sessions_governed_purge_delete
  BEFORE DELETE ON public.upload_sessions
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();
CREATE TRIGGER zz_document_upload_receipts_governed_purge_delete
  BEFORE DELETE ON public.document_upload_command_receipts
  FOR EACH ROW EXECUTE FUNCTION public.governed_trash_purge_dependency_delete_guard();

-- TRUNCATE bypasses row-level DELETE triggers and FK action checks. There is
-- no legitimate purge use for it, so reject it for every directly reachable
-- hierarchy table even for a postgres-like session that has table ownership.
CREATE FUNCTION public.managed_hierarchy_prevent_truncate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'TRUNCATE is not permitted for governed hierarchy data';
END;
$$;

CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.clients FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.matters FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.documents FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_links FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.supporting_documents FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.supporting_doc_links FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.deadlines FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.case_notes FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.wiki_sections FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.wiki_section_versions FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.ai_usage_logs FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_relationship_placement_effects FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_processing_runs FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_processing_recovery_cases FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_effective_metadata FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_command_receipts FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.intake_item_assignments FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.intake_items FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.upload_sessions FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_upload_command_receipts FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();

-- Replace the older fence-only lifecycle guards. They now require that the
-- row itself belongs to the fenced job's exact operation, not merely that a
-- concurrent purge happens to exist in this transaction.
CREATE OR REPLACE FUNCTION public.document_lifecycle_prevent_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF session_user='postgres' AND TG_TABLE_NAME='outbox_events'
     AND current_setting('document_lifecycle.outbox_compaction_delete',true)='on' THEN RETURN OLD; END IF;
  CASE TG_TABLE_NAME
    WHEN 'document_versions' THEN
      IF public.trash_purge_current_job_owns_resource(OLD.org_id,'document',OLD.document_id) THEN RETURN OLD; END IF;
    WHEN 'document_version_analysis_bindings' THEN
      IF EXISTS (SELECT 1 FROM public.document_versions version
        WHERE version.org_id=OLD.org_id AND version.id=OLD.document_version_id
          AND public.trash_purge_current_job_owns_resource(version.org_id,'document',version.document_id)) THEN RETURN OLD; END IF;
    WHEN 'file_assets' THEN
      IF public.trash_purge_current_job_owns_asset(OLD.org_id,OLD.id) THEN RETURN OLD; END IF;
    WHEN 'source_analysis_runs' THEN
      IF public.trash_purge_current_job_owns_asset(OLD.org_id,OLD.asset_id) THEN RETURN OLD; END IF;
    WHEN 'storage_reservations' THEN
      IF EXISTS (SELECT 1 FROM public.upload_sessions s WHERE s.id=OLD.upload_session_id
        AND public.trash_purge_current_job_owns_asset(s.org_id,s.asset_id)) THEN RETURN OLD; END IF;
  END CASE;
  RAISE EXCEPTION 'lifecycle records require the exact authorised Trash purge boundary';
END $$;
CREATE OR REPLACE FUNCTION public.source_analysis_provenance_prevent_attempt_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.source_analysis_runs run WHERE run.id=OLD.source_analysis_run_id
    AND public.trash_purge_current_job_owns_asset(run.org_id,run.asset_id)) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'source analysis attempts require the exact authorised Trash purge boundary';
END $$;
CREATE OR REPLACE FUNCTION public.source_field_candidate_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND public.trash_purge_current_job_owns_asset(OLD.org_id,OLD.asset_id) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'source field candidates are immutable once materialized';
END $$;
CREATE OR REPLACE FUNCTION public.document_field_candidate_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND public.trash_purge_current_job_owns_resource(OLD.org_id,'document',OLD.document_id) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'document field candidates are immutable once materialized';
END $$;
CREATE OR REPLACE FUNCTION public.document_field_decision_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND public.trash_purge_current_job_owns_resource(OLD.org_id,'document',OLD.document_id) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'document field decisions are append-only and immutable';
END $$;

-- `matters.financial_year` is a required legacy schema field. The permanent
-- delete shell must not violate that constraint; the empty default is an
-- intentionally non-content placeholder and is applied only by this exact
-- fenced matter purge transition.
CREATE FUNCTION public.normalize_purged_matter_financial_year()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.financial_year IS NULL AND NEW.title='Permanently deleted'
     AND public.trash_purge_current_job_owns_resource(OLD.org_id,'matter',OLD.id) THEN
    NEW.financial_year := '';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER aa_matters_normalize_purged_financial_year
  BEFORE UPDATE OF title,financial_year ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.normalize_purged_matter_financial_year();

CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.file_assets FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_versions FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_version_analysis_bindings FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.source_analysis_runs FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.source_analysis_attempts FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.source_field_candidates FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_field_candidates FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.document_field_decisions FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.storage_reservations FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.notifications FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.activity_logs FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();
CREATE TRIGGER managed_hierarchy_no_truncate BEFORE TRUNCATE ON public.outbox_events FOR EACH STATEMENT EXECUTE FUNCTION public.managed_hierarchy_prevent_truncate();

REVOKE DELETE, TRUNCATE ON TABLE
  public.document_links, public.supporting_doc_links, public.deadlines,
  public.case_notes, public.wiki_sections, public.wiki_section_versions,
  public.ai_usage_logs, public.document_relationship_placement_effects,
  public.document_processing_runs, public.document_processing_recovery_cases,
  public.document_command_receipts,
  public.intake_item_assignments, public.intake_items, public.upload_sessions,
  public.document_upload_command_receipts, public.file_assets, public.document_versions,
  public.document_version_analysis_bindings, public.source_analysis_runs,
  public.source_analysis_attempts, public.source_field_candidates,
  public.document_field_candidates, public.document_field_decisions,
  public.storage_reservations, public.notifications, public.activity_logs,
  public.outbox_events
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trash_purge_current_job_owns_resource(uuid,public.trash_resource_type,uuid),
  public.trash_purge_current_job_owns_asset(uuid,uuid), public.governed_trash_purge_dependency_delete_guard(),
  public.governed_wiki_section_purge_cleanup(), public.managed_hierarchy_prevent_truncate(),
  public.normalize_purged_matter_financial_year()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.governed_trash_purge_dependency_delete_guard() IS
  'Allows hierarchy-dependent physical deletion only within the current transaction of a running, unexpired, service-only Trash purge lease.';
COMMENT ON FUNCTION public.managed_hierarchy_prevent_truncate() IS
  'Fail-closed TRUNCATE fence for hierarchy roots and their governed dependent data.';

COMMIT;
