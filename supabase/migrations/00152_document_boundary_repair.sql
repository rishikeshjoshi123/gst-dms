-- Explicit one-document repair. Existing Matter creation and ordinary upload
-- remain separate authorities; this command is the only shared-asset Copy.
BEGIN;

-- Historical identifier evidence belongs to its original Matter decision,
-- while its immutable document/version locator can survive a later Move.
-- Active obligations are enforced independently at the document boundary.
ALTER TABLE public.matter_identifiers DROP CONSTRAINT matter_identifiers_evidence_document_fkey;
ALTER TABLE public.matter_identifiers ADD CONSTRAINT matter_identifiers_evidence_document_fkey
  FOREIGN KEY (org_id,evidence_document_id) REFERENCES public.documents(org_id,id) ON DELETE RESTRICT;

ALTER TABLE public.document_field_decisions ADD COLUMN inherited_from_decision_id uuid;
COMMENT ON COLUMN public.document_field_decisions.inherited_from_decision_id IS
  'Immutable source decision locator for an explicit Copy. Insert-validated; no FK so source purge does not delete or prevent retention of the copied decision.';
ALTER TABLE public.document_page_text_artifacts ADD COLUMN copied_from_artifact_id uuid;
COMMENT ON COLUMN public.document_page_text_artifacts.copied_from_artifact_id IS
  'Original approved page acquisition locator reused by Copy; copied pages retain acquisition provenance independently of source purge.';

CREATE FUNCTION public.document_boundary_inherited_decision_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.inherited_from_decision_id IS NULL THEN RETURN NEW; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.document_field_decisions original
    JOIN public.document_field_candidates source_candidate ON source_candidate.id=original.document_field_candidate_id
    JOIN public.document_field_candidates destination ON destination.id=NEW.document_field_candidate_id
    JOIN public.documents copy ON copy.id=NEW.document_id AND copy.org_id=NEW.org_id
    WHERE original.id=NEW.inherited_from_decision_id AND original.org_id=NEW.org_id
      AND copy.copied_from_document_id=original.document_id
      AND destination.document_id=copy.id AND destination.org_id=original.org_id
      AND destination.source_field_candidate_id=source_candidate.source_field_candidate_id
      AND NEW.action=original.action AND NEW.replacement_value IS NOT DISTINCT FROM original.replacement_value
  ) THEN RAISE EXCEPTION 'Inherited field decision must preserve exact Copy provenance'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_boundary_inherited_decision_guard BEFORE INSERT ON public.document_field_decisions
  FOR EACH ROW EXECUTE FUNCTION public.document_boundary_inherited_decision_guard();

-- Mutations serialize only with the affected document(s), never a whole
-- dependency table. This also fences non-FK Task/Trash locators and ordinary
-- updates whose unchanged foreign keys would otherwise acquire no row lock.
CREATE FUNCTION public.document_boundary_dependency_lock() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE row_json jsonb; ids uuid[]:='{}'; key text; document_key uuid;
BEGIN
  FOR row_json IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
    CASE WHEN TG_OP<>'INSERT' THEN to_jsonb(OLD) END,CASE WHEN TG_OP<>'DELETE' THEN to_jsonb(NEW) END)) LOOP
    FOREACH key IN ARRAY ARRAY['document_id','source_document_id','target_document_id','from_doc_id','to_doc_id','evidence_document_id'] LOOP
      IF row_json->>key IS NOT NULL THEN ids:=array_append(ids,(row_json->>key)::uuid); END IF;
    END LOOP;
    IF row_json->>'resource_type'='document' THEN ids:=array_append(ids,(row_json->>'resource_id')::uuid); END IF;
    IF row_json->>'mention_id' IS NOT NULL THEN
      SELECT source_document_id INTO document_key FROM public.document_reference_mentions WHERE id=(row_json->>'mention_id')::uuid;
      ids:=array_append(ids,document_key);
    END IF;
    IF row_json->>'artifact_id' IS NOT NULL THEN
      SELECT document_id INTO document_key FROM public.document_page_text_artifacts WHERE id=(row_json->>'artifact_id')::uuid;
      ids:=array_append(ids,document_key);
    END IF;
  END LOOP;
  FOR document_key IN SELECT DISTINCT value FROM unnest(ids) value WHERE value IS NOT NULL ORDER BY value LOOP
    PERFORM pg_advisory_xact_lock_shared(hashtextextended(document_key::text,1521));
  END LOOP;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
DO $$ DECLARE dependency text; BEGIN
  FOREACH dependency IN ARRAY ARRAY['case_notes','deadlines','tasks','document_processing_runs',
    'document_self_identifiers','matter_identifiers','document_reference_mentions','current_document_reference_resolutions',
    'document_relationships','document_links','supporting_doc_links','document_effective_metadata',
    'document_field_candidates','document_field_decisions','document_version_analysis_bindings',
    'document_page_text_artifacts','document_page_text_pages','resource_trash_memberships'] LOOP
    EXECUTE format('CREATE TRIGGER boundary_dependency_lock BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.document_boundary_dependency_lock()',dependency);
  END LOOP;
END $$;

CREATE FUNCTION public.document_boundary_active_identity_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.matter_id IS DISTINCT FROM OLD.matter_id AND (
    EXISTS(SELECT 1 FROM public.matter_identifiers WHERE evidence_document_id=OLD.id AND lifecycle_state='active')
    OR EXISTS(SELECT 1 FROM public.document_self_identifiers i JOIN public.matter_identifiers m ON m.id=i.matter_identifier_id
      WHERE i.document_id=OLD.id AND i.lifecycle_state='active' AND m.lifecycle_state='active')
  ) THEN RAISE EXCEPTION 'Active Matter identity evidence prevents this Move'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_boundary_active_identity_guard BEFORE UPDATE OF matter_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.document_boundary_active_identity_guard();

ALTER TABLE public.note_document_quotes
  ALTER CONSTRAINT note_document_quotes_note_lineage_fkey DEFERRABLE INITIALLY IMMEDIATE,
  ALTER CONSTRAINT note_document_quotes_document_lineage_fkey DEFERRABLE INITIALLY IMMEDIATE;

CREATE TABLE public.document_boundary_repair_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  mode text NOT NULL CHECK (mode IN ('move','copy')),
  source_document_id uuid NOT NULL,
  source_matter_id uuid NOT NULL,
  target_matter_id uuid NOT NULL,
  result_document_id uuid NOT NULL,
  result_version_id uuid NOT NULL,
  reason text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]'),
  impact jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.document_boundary_repair_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_boundary_repair_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.document_boundary_repair_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER document_boundary_repair_receipts_immutable BEFORE UPDATE OR DELETE
  ON public.document_boundary_repair_receipts FOR EACH ROW
  EXECUTE FUNCTION public.relationship_decisions_prevent_mutation();

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES ('document.boundary_repaired',1,'record',ARRAY['document'],'matter','{"mode":"code"}','document.boundary_repaired');

-- The legacy deadline table has no tenant column. Its context must follow the
-- locked document even when a compatibility writer races a repair.
CREATE FUNCTION public.document_boundary_dependent_context_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.documents%ROWTYPE;
BEGIN
  IF NEW.document_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO d FROM public.documents WHERE id=NEW.document_id FOR SHARE;
  IF d.id IS NULL OR d.matter_id IS DISTINCT FROM NEW.matter_id
     OR (TG_TABLE_NAME <> 'deadlines' AND to_jsonb(NEW)->>'org_id' IS DISTINCT FROM d.org_id::text) THEN
    RAISE EXCEPTION 'Document dependent context is unavailable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER deadlines_boundary_context BEFORE INSERT OR UPDATE OF document_id,matter_id ON public.deadlines
  FOR EACH ROW EXECUTE FUNCTION public.document_boundary_dependent_context_guard();
CREATE TRIGGER case_notes_boundary_context BEFORE INSERT OR UPDATE OF document_id,matter_id ON public.case_notes
  FOR EACH ROW EXECUTE FUNCTION public.document_boundary_dependent_context_guard();
CREATE TRIGGER tasks_boundary_context BEFORE INSERT OR UPDATE OF document_id,matter_id ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.document_boundary_dependent_context_guard();

CREATE FUNCTION public.document_boundary_repair_impact(p_org uuid,p_document uuid,p_target uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.documents%ROWTYPE; source_m public.matters%ROWTYPE; target_m public.matters%ROWTYPE;
  v public.document_versions%ROWTYPE; a public.file_assets%ROWTYPE; row_data record;
  state jsonb; impact jsonb; blockers jsonb:='[]'; categories jsonb:='[]'; count_rows integer;
BEGIN
  IF p_document IS NULL OR p_target IS NULL OR p_mode IS NULL OR p_mode NOT IN ('move','copy') THEN
    RETURN jsonb_build_object('code','invalid_request');
  END IF;
  SELECT * INTO d FROM public.documents WHERE id=p_document AND org_id=p_org;
  IF d.id IS NULL THEN RETURN jsonb_build_object('code','context_unavailable'); END IF;
  -- Shared dependency fences remain mutually compatible during ordinary
  -- exact-reference resolution (which has its own ordered key locks).
  -- Only this boundary operation takes the exclusive document fence.
  PERFORM pg_advisory_xact_lock(hashtextextended(d.id::text,1521));
  -- Match the effective-relationship authority's Matter fence, in UUID order.
  FOR row_data IN SELECT id FROM public.matters WHERE org_id=p_org AND id IN(d.matter_id,p_target) ORDER BY id LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(p_org::text||':'||row_data.id::text,146));
  END LOOP;
  PERFORM 1 FROM public.clients WHERE org_id=p_org AND id IN(SELECT client_id FROM public.matters WHERE id IN(d.matter_id,p_target)) ORDER BY id FOR SHARE;
  PERFORM 1 FROM public.matters WHERE org_id=p_org AND id IN(d.matter_id,p_target) ORDER BY id FOR UPDATE;
  SELECT * INTO source_m FROM public.matters WHERE id=d.matter_id AND org_id=p_org;
  SELECT * INTO target_m FROM public.matters WHERE id=p_target AND org_id=p_org;
  SELECT * INTO d FROM public.documents WHERE id=p_document AND org_id=p_org FOR UPDATE;
  IF source_m.id IS NULL OR target_m.id IS NULL OR d.matter_id<>source_m.id
     OR source_m.id=target_m.id OR source_m.record_state<>'active' OR target_m.record_state<>'active'
     OR source_m.deleted_at IS NOT NULL OR target_m.deleted_at IS NOT NULL
     OR source_m.work_state='closed' OR target_m.work_state='closed'
     OR d.record_state<>'active' OR d.deleted_at IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.clients WHERE id IN(source_m.client_id,target_m.client_id) AND (record_state<>'active' OR deleted_at IS NOT NULL)) THEN
    RETURN jsonb_build_object('code','context_unavailable');
  END IF;
  SELECT * INTO v FROM public.document_versions WHERE id=d.current_version_id AND org_id=p_org AND document_id=d.id FOR UPDATE;
  SELECT * INTO a FROM public.file_assets WHERE id=v.asset_id AND org_id=p_org FOR UPDATE;
  IF v.id IS NULL OR v.state<>'current' OR v.validation_state<>'valid' OR a.id IS NULL
     OR a.availability<>'available' OR a.storage_deleted_at IS NOT NULL OR d.content_availability NOT IN ('source_attached','source_indexed') THEN
    RETURN jsonb_build_object('code','source_unavailable');
  END IF;
  -- The document UPDATE lock and dependency triggers stop scoped mutations
  -- and insertion phantoms. Explicit row order keeps dependent readers stable.
  PERFORM 1 FROM public.case_notes WHERE document_id=d.id ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.tasks WHERE document_id=d.id ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.deadlines WHERE document_id=d.id ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.document_processing_runs WHERE document_id=d.id ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.document_page_text_artifacts WHERE document_id=d.id ORDER BY id FOR UPDATE;
  state:=jsonb_build_object('document',to_jsonb(d),'source',to_jsonb(source_m),'target',to_jsonb(target_m),'version',to_jsonb(v),'asset',to_jsonb(a));
  FOR row_data IN
    SELECT 'document_identifiers' AS key, 'Verified document identifiers' AS label,
      coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') AS rows FROM public.document_self_identifiers i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'matter_identifiers','Matter identifier evidence',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.matter_identifiers i WHERE i.org_id=p_org AND i.evidence_document_id=d.id
    UNION ALL SELECT 'references','Reference mentions',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_reference_mentions i WHERE i.org_id=p_org AND i.source_document_id=d.id
    UNION ALL SELECT 'reference_resolutions','Current reference resolutions',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.mention_id),'[]') FROM public.current_document_reference_resolutions i WHERE i.org_id=p_org AND (i.target_document_id=d.id OR EXISTS(SELECT 1 FROM public.document_reference_mentions mention WHERE mention.id=i.mention_id AND mention.source_document_id=d.id))
    UNION ALL SELECT 'relationships','Effective relationships',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_relationships i WHERE i.org_id=p_org AND d.id IN(i.source_document_id,i.target_document_id) AND i.lifecycle_state='active'
    UNION ALL SELECT 'legacy_links','Legacy links',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_links i WHERE d.id IN(i.from_doc_id,i.to_doc_id)
    UNION ALL SELECT 'deadlines','Document deadlines',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.deadlines i WHERE i.document_id=d.id
    UNION ALL SELECT 'notes','Document notes',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.case_notes i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'citations','Exact source citations',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.note_id),'[]') FROM public.note_document_quotes i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'tasks','Document tasks',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.tasks i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'effective_fields','Effective document fields',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_effective_metadata i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'financial_facts','Financial source facts',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_field_candidates i WHERE i.org_id=p_org AND i.document_id=d.id AND i.field_path LIKE 'document.money.%'
    UNION ALL SELECT 'analyses','Shared base analyses',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_version_analysis_bindings i WHERE i.org_id=p_org AND i.document_version_id=v.id
    UNION ALL SELECT 'page_acquisition','Retained page acquisition',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_page_text_artifacts i WHERE i.org_id=p_org AND i.document_version_id=v.id
    UNION ALL SELECT 'processing','Document processing attempts',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.document_processing_runs i WHERE i.org_id=p_org AND i.document_id=d.id
    UNION ALL SELECT 'trash_conflicts','Trash and Restore conflicts',coalesce(jsonb_agg(to_jsonb(i) ORDER BY i.id),'[]') FROM public.resource_trash_memberships i WHERE i.org_id=p_org AND i.state='active' AND i.resource_id IN(d.id,source_m.id,target_m.id,source_m.client_id,target_m.client_id)
  LOOP
    count_rows:=jsonb_array_length(row_data.rows);
    IF count_rows>1000 THEN RETURN jsonb_build_object('code','impact_too_large'); END IF;
    state:=state||jsonb_build_object(row_data.key,row_data.rows);
    categories:=categories||jsonb_build_array(jsonb_build_object('key',row_data.key,'label',row_data.label,'count',count_rows));
  END LOOP;
  IF jsonb_array_length(state->'trash_conflicts')>0 THEN blockers:=blockers||'"Resolve the active Trash or Restore conflict first."'::jsonb; END IF;
  IF EXISTS(SELECT 1 FROM public.document_processing_runs processing WHERE processing.org_id=p_org AND processing.document_id=d.id AND processing.state IN('queued','running')) THEN blockers:=blockers||'"Wait for document processing to finish."'::jsonb; END IF;
  IF p_mode='move' THEN
    IF EXISTS(SELECT 1 FROM public.matter_identifiers WHERE evidence_document_id=d.id AND lifecycle_state='active')
      OR EXISTS(SELECT 1 FROM public.document_self_identifiers i JOIN public.matter_identifiers m ON m.id=i.matter_identifier_id WHERE i.org_id=p_org AND i.document_id=d.id AND i.lifecycle_state='active' AND m.lifecycle_state='active') THEN
      blockers:=blockers||'"This document anchors a Matter identifier. Resolve that identifier evidence before moving it."'::jsonb;
    END IF;
    IF jsonb_array_length(state->'legacy_links')>0 OR EXISTS(SELECT 1 FROM public.supporting_doc_links WHERE document_id=d.id) THEN blockers:=blockers||'"Legacy links require governed relationship review before this document can move."'::jsonb; END IF;
    IF EXISTS(SELECT 1 FROM public.case_notes n JOIN public.case_notes related ON related.id=n.parent_note_id OR related.parent_note_id=n.id WHERE n.document_id=d.id AND related.document_id IS DISTINCT FROM d.id) THEN blockers:=blockers||'"A note thread includes another document or Matter note. Resolve the thread context before moving."'::jsonb; END IF;
    IF EXISTS(SELECT 1 FROM public.tasks WHERE org_id=p_org AND document_id=d.id AND (status='suspended' OR matter_id<>source_m.id)) THEN blockers:=blockers||'"A suspended or conflicting task requires review before moving."'::jsonb; END IF;
    IF EXISTS(SELECT 1 FROM public.note_document_quotes q JOIN public.case_notes n ON n.id=q.note_id WHERE q.document_id=d.id AND n.document_id IS DISTINCT FROM d.id) THEN blockers:=blockers||'"A citation belongs to a separate Matter note and requires review before moving."'::jsonb; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.document_page_text_artifacts artifact WHERE artifact.document_version_id=v.id AND artifact.state='ready' AND public.document_page_text_artifact_has_approved_acquisition(artifact.id,artifact.page_count)) THEN
      blockers:=blockers||'"Retained approved page acquisition is required before copying this source."'::jsonb;
    END IF;
    IF EXISTS(SELECT 1 FROM public.document_versions other_v JOIN public.documents other_d ON other_d.id=other_v.document_id WHERE other_v.org_id=p_org AND other_v.asset_id=a.id AND other_d.matter_id=p_target) THEN blockers:=blockers||'"The target Matter already contains this source, including retained version history or Trash. Open or restore that document."'::jsonb; END IF;
  END IF;
  impact:=jsonb_build_object('code','ok','documentId',d.id,'documentTitle',coalesce(d.display_title,v.original_filename),
    'sourceMatterId',source_m.id,'sourceMatterTitle',source_m.title,'targetMatterId',target_m.id,'targetMatterTitle',target_m.title,
    'mode',p_mode,'documentRevision',d.lifecycle_revision,'sourceRevision',source_m.revision,'targetRevision',target_m.revision,
    'versionId',v.id,'sharedAssets',1,'categories',categories,'blockers',blockers,
    'fingerprint',encode(extensions.digest(convert_to(state::text||p_mode,'utf8'),'sha256'),'hex'));
  RETURN impact;
END $$;

CREATE FUNCTION public.preview_document_boundary_repair(p_document_id uuid,p_target_matter_id uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.lock_matter_identifier_actor();
  IF actor.org_id IS NULL THEN RETURN jsonb_build_object('code','not_allowed'); END IF;
  RETURN public.document_boundary_repair_impact(actor.org_id,p_document_id,p_target_matter_id,p_mode);
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN jsonb_build_object('code','busy');
END $$;

CREATE FUNCTION public.execute_document_boundary_repair(p_document_id uuid,p_target_matter_id uuid,p_mode text,
  p_expected_fingerprint text,p_reason text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public SET lock_timeout='5s' AS $$
DECLARE actor record; prior public.document_boundary_repair_receipts%ROWTYPE; impact jsonb; fingerprint text;
  reason text:=nullif(btrim(p_reason),''); d public.documents%ROWTYPE; v public.document_versions%ROWTYPE;
  result_doc uuid; result_version uuid; binding record; binding_id uuid; edge public.document_relationships%ROWTYPE; key_row record; search_event uuid;
  source_decision record; destination_candidate uuid; search_run uuid; source_artifact public.document_page_text_artifacts%ROWTYPE; copied_artifact uuid;
BEGIN
  IF p_idempotency_key IS NULL OR p_expected_fingerprint IS NULL OR p_expected_fingerprint !~ '^[0-9a-f]{64}$'
     OR NOT public.matter_identifier_reason_is_safe(reason,true) THEN RETURN jsonb_build_object('code','invalid_request'); END IF;
  SELECT * INTO actor FROM public.lock_matter_identifier_actor();
  IF actor.org_id IS NULL THEN RETURN jsonb_build_object('code','not_allowed'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key::text,152));
  fingerprint:=encode(extensions.digest(convert_to(jsonb_build_array(p_document_id,p_target_matter_id,p_mode,p_expected_fingerprint,reason)::text,'utf8'),'sha256'),'hex');
  SELECT * INTO prior FROM public.document_boundary_repair_receipts WHERE idempotency_key=p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.org_id<>actor.org_id OR prior.actor_user_id<>actor.actor_user_id OR prior.request_fingerprint<>fingerprint THEN RETURN jsonb_build_object('code','idempotency_conflict'); END IF;
    RETURN jsonb_build_object('code','ok','documentId',prior.result_document_id,'sourceMatterId',prior.source_matter_id,'targetMatterId',prior.target_matter_id,'replayed',true);
  END IF;
  impact:=public.document_boundary_repair_impact(actor.org_id,p_document_id,p_target_matter_id,p_mode);
  IF impact->>'code'<>'ok' THEN RETURN impact; END IF;
  IF impact->>'fingerprint'<>p_expected_fingerprint THEN RETURN jsonb_build_object('code','stale_preview'); END IF;
  IF jsonb_array_length(impact->'blockers')>0 THEN RETURN jsonb_build_object('code','blocked'); END IF;
  SELECT * INTO d FROM public.documents WHERE id=p_document_id;
  SELECT * INTO v FROM public.document_versions WHERE id=d.current_version_id;
  IF p_mode='move' THEN
    FOR edge IN SELECT * FROM public.document_relationships WHERE org_id=actor.org_id AND d.id IN(source_document_id,target_document_id) AND lifecycle_state='active' ORDER BY id LOOP
      UPDATE public.document_relationships SET lifecycle_state='archived',revision=revision+1,archived_at=now(),archived_by=actor.actor_user_id,archive_reason=reason,updated_at=now() WHERE id=edge.id;
      INSERT INTO public.document_relationship_decisions(org_id,matter_id,relationship_id,source_document_id,target_document_id,relationship_type,action,from_lifecycle,to_lifecycle,reason,actor_user_id,resulting_revision,idempotency_key)
      VALUES(edge.org_id,edge.matter_id,edge.id,edge.source_document_id,edge.target_document_id,edge.relationship_type,'archive','active','archived',reason,actor.actor_user_id,edge.revision+1,gen_random_uuid());
    END LOOP;
    SET CONSTRAINTS note_document_quotes_note_lineage_fkey,note_document_quotes_document_lineage_fkey DEFERRED;
    UPDATE public.documents SET matter_id=p_target_matter_id,content_availability='source_attached',
      embedding=NULL,embedding_model=NULL,embedding_version=NULL,embedding_document_version_id=NULL WHERE id=d.id;
    UPDATE public.case_notes SET matter_id=p_target_matter_id WHERE org_id=actor.org_id AND document_id=d.id;
    UPDATE public.note_document_quotes SET matter_id=p_target_matter_id WHERE org_id=actor.org_id AND document_id=d.id;
    UPDATE public.deadlines SET matter_id=p_target_matter_id WHERE document_id=d.id;
    UPDATE public.tasks SET matter_id=p_target_matter_id,client_id=(SELECT client_id FROM public.matters WHERE id=p_target_matter_id),revision=revision+1,updated_at=now() WHERE org_id=actor.org_id AND document_id=d.id;
    SET CONSTRAINTS note_document_quotes_note_lineage_fkey,note_document_quotes_document_lineage_fkey IMMEDIATE;
    result_doc:=d.id; result_version:=v.id;
    FOR key_row IN SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_self_identifiers WHERE org_id=actor.org_id AND document_id=d.id
      UNION SELECT DISTINCT org_id,issuer_namespace_normalized,identifier_kind,normalized_value FROM public.document_reference_mentions WHERE org_id=actor.org_id AND source_document_id=d.id ORDER BY org_id,issuer_namespace_normalized,identifier_kind,normalized_value LOOP
      PERFORM public.reevaluate_document_reference_exact_key(key_row.org_id,key_row.issuer_namespace_normalized,key_row.identifier_kind,key_row.normalized_value,'document_availability_changed','repair.'||p_idempotency_key::text||'.'||md5(key_row.issuer_namespace_normalized||key_row.identifier_kind::text||key_row.normalized_value));
    END LOOP;
  ELSE
    INSERT INTO public.documents(org_id,matter_id,display_title,document_class,document_category,origin_kind,copied_from_document_id,content_availability,status,created_by,doc_type,reference_number,doc_date,direction,issued_by,financial_year,summary)
    VALUES(d.org_id,p_target_matter_id,d.display_title,d.document_class,d.document_category,d.origin_kind,d.id,'metadata_only','placed',actor.actor_user_id,d.doc_type,d.reference_number,d.doc_date,d.direction,d.issued_by,d.financial_year,d.summary) RETURNING id INTO result_doc;
    INSERT INTO public.document_versions(org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,created_by,validated_at,promoted_at)
    VALUES(d.org_id,result_doc,v.asset_id,1,v.original_filename,v.page_count,'valid','current',actor.actor_user_id,v.validated_at,now()) RETURNING id INTO result_version;
    UPDATE public.documents SET current_version_id=result_version,content_availability='source_attached',effective_filename=v.original_filename,effective_size_bytes=d.effective_size_bytes WHERE id=result_doc;
    FOR binding IN SELECT * FROM public.document_version_analysis_bindings WHERE org_id=d.org_id AND document_version_id=v.id ORDER BY id LOOP
      binding_id:=public.materialize_document_version_analysis(result_version,binding.source_analysis_run_id,'boundary_copy',actor.actor_user_id);
      PERFORM public.materialize_document_reference_mentions(binding_id,'repair.'||p_idempotency_key::text||'.'||binding_id::text);
    END LOOP;
    -- Preserve each current human outcome, including negative decisions that
    -- suppress AI fallback. The copied decision records the confirming actor
    -- and the exact original decision locator; verified identities are separate.
    FOR source_decision IN
      SELECT decision.*, candidate.source_field_candidate_id
      FROM public.document_effective_metadata effective
      JOIN public.document_field_decisions decision ON decision.id=effective.winning_document_field_decision_id
      JOIN public.document_field_candidates candidate ON candidate.id=decision.document_field_candidate_id
      WHERE effective.document_version_id=v.id AND effective.org_id=d.org_id ORDER BY decision.decision_sequence
    LOOP
      SELECT id INTO destination_candidate FROM public.document_field_candidates
      WHERE document_version_id=result_version AND source_field_candidate_id=source_decision.source_field_candidate_id;
      IF destination_candidate IS NULL THEN RAISE EXCEPTION 'Copy decision candidate is unavailable'; END IF;
      INSERT INTO public.document_field_decisions(org_id,document_id,document_version_id,document_field_candidate_id,semantic_candidate_key,field_path,value_type,
        action,replacement_value,reason,actor_user_id,idempotency_key,inherited_from_decision_id)
      VALUES(d.org_id,result_doc,result_version,destination_candidate,source_decision.semantic_candidate_key,source_decision.field_path,source_decision.value_type,
        source_decision.action,source_decision.replacement_value,'Inherited through explicit document Copy',actor.actor_user_id,
        'copy.'||p_idempotency_key::text||'.'||source_decision.id::text,source_decision.id);
    END LOOP;
    PERFORM public.recompute_document_effective_metadata(result_version);
  END IF;
  -- Invalidate all current Search facts and append the existing fenced,
  -- version-scoped Search worker intent. No base extraction/provider request.
  PERFORM public.invalidate_current_document_structured_search_facts(d.org_id,result_doc);
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(d.org_id,'document',result_doc,'document.reprocess_requested.v1',
    jsonb_build_object('document_id',result_doc::text,'version_id',result_version::text,'scope','search_index'),
    'document.repair.search.'||p_idempotency_key::text) RETURNING id INTO search_event;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,scope,stage,state,idempotency_key,outbox_event_id)
  VALUES(d.org_id,result_doc,result_version,'search_index','queued','queued','repair.search.'||p_idempotency_key::text,search_event) RETURNING id INTO search_run;
  IF p_mode='copy' THEN
    SELECT * INTO source_artifact FROM public.document_page_text_artifacts WHERE document_version_id=v.id AND org_id=d.org_id AND state='ready';
    IF source_artifact.id IS NULL OR NOT public.document_page_text_artifact_has_approved_acquisition(source_artifact.id,source_artifact.page_count) THEN RAISE EXCEPTION 'Approved Copy page source is unavailable'; END IF;
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint,copied_from_artifact_id)
    VALUES(d.org_id,result_doc,result_version,search_run,source_artifact.source_analysis_run_id,'ready',source_artifact.page_count,source_artifact.content_fingerprint,source_artifact.id) RETURNING id INTO copied_artifact;
    INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version)
    SELECT org_id,copied_artifact,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version
    FROM public.document_page_text_pages WHERE artifact_id=source_artifact.id ORDER BY page_number;
  END IF;
  PERFORM public.append_activity_event(d.org_id,'document.boundary_repaired',1::smallint,'user',actor.actor_user_id,'Member','document',result_doc,
    (SELECT client_id FROM public.matters WHERE id=p_target_matter_id),p_target_matter_id,'Document','Document '||CASE p_mode WHEN 'move' THEN 'moved' ELSE 'copied' END,
    jsonb_build_object('mode',p_mode),'document',result_doc,result_version,p_idempotency_key,NULL,'document.repair.'||p_idempotency_key::text,now());
  INSERT INTO public.document_boundary_repair_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,mode,source_document_id,source_matter_id,target_matter_id,result_document_id,result_version_id,reason,impact)
  VALUES(d.org_id,actor.actor_user_id,p_idempotency_key,fingerprint,p_mode,d.id,d.matter_id,p_target_matter_id,result_doc,result_version,reason,
    jsonb_build_object('documentId',d.id,'sourceMatterId',d.matter_id,'targetMatterId',p_target_matter_id,'versionId',v.id,
      'fingerprint',impact->>'fingerprint','documentRevision',impact->'documentRevision','sourceRevision',impact->'sourceRevision','targetRevision',impact->'targetRevision',
      'counts',(SELECT jsonb_object_agg(category->>'key',category->'count') FROM jsonb_array_elements(impact->'categories') category)));
  RETURN jsonb_build_object('code','ok','documentId',result_doc,'sourceMatterId',d.matter_id,'targetMatterId',p_target_matter_id,'replayed',false);
EXCEPTION WHEN lock_not_available OR deadlock_detected THEN RETURN jsonb_build_object('code','busy');
  WHEN others THEN RETURN jsonb_build_object('code','write_failed');
END $$;

REVOKE ALL ON FUNCTION public.document_boundary_dependent_context_guard(),public.document_boundary_repair_impact(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.document_boundary_inherited_decision_guard(),public.document_boundary_dependency_lock(),public.document_boundary_active_identity_guard() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.preview_document_boundary_repair(uuid,uuid,text),public.execute_document_boundary_repair(uuid,uuid,text,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_document_boundary_repair(uuid,uuid,text),public.execute_document_boundary_repair(uuid,uuid,text,text,text,uuid) TO authenticated;
COMMIT;
