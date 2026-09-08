-- Authoritative immutable source locators for the enabled legacy Notes adapter.
BEGIN;

ALTER TABLE public.case_notes
  ADD CONSTRAINT case_notes_org_matter_id_unique UNIQUE (org_id, matter_id, id);
ALTER TABLE public.documents
  ADD CONSTRAINT documents_org_matter_id_unique UNIQUE (org_id, matter_id, id);
ALTER TABLE public.document_versions
  ADD CONSTRAINT document_versions_org_document_id_unique UNIQUE (org_id, document_id, id);

CREATE TYPE public.note_quote_selection_method AS ENUM ('text');

CREATE TABLE public.note_document_quotes (
  note_id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  page_number integer NOT NULL CHECK (page_number > 0),
  excerpt text NOT NULL CHECK (btrim(excerpt) <> '' AND char_length(excerpt) <= 20000),
  selection_method public.note_quote_selection_method NOT NULL DEFAULT 'text',
  regions jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT note_document_quotes_note_lineage_fkey
    FOREIGN KEY (org_id, matter_id, note_id)
    REFERENCES public.case_notes(org_id, matter_id, id) ON DELETE CASCADE,
  CONSTRAINT note_document_quotes_document_lineage_fkey
    FOREIGN KEY (org_id, matter_id, document_id)
    REFERENCES public.documents(org_id, matter_id, id) ON DELETE RESTRICT,
  CONSTRAINT note_document_quotes_version_lineage_fkey
    FOREIGN KEY (org_id, document_id, document_version_id)
    REFERENCES public.document_versions(org_id, document_id, id) ON DELETE RESTRICT,
  CONSTRAINT note_document_quotes_region_shape CHECK (
    regions IS NULL OR (jsonb_typeof(regions) = 'array' AND jsonb_array_length(regions) > 0)
  )
);
CREATE INDEX note_document_quotes_version_idx
  ON public.note_document_quotes(org_id, document_version_id, note_id);

ALTER TABLE public.note_document_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.note_document_quotes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.note_document_quotes FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.protect_legacy_note_quote_columns()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.quote IS DISTINCT FROM OLD.quote OR NEW.page_number IS DISTINCT FROM OLD.page_number THEN
    RAISE EXCEPTION 'legacy note quotation fields are command-managed';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER case_notes_protect_legacy_quote_columns
  BEFORE UPDATE OF quote, page_number ON public.case_notes
  FOR EACH ROW EXECUTE FUNCTION public.protect_legacy_note_quote_columns();
REVOKE ALL ON FUNCTION public.protect_legacy_note_quote_columns() FROM PUBLIC, anon, authenticated, service_role;

-- The governed purge deletes versions before legacy notes. Remove only the
-- locator leaf while its transaction-scoped purge fence is present; ordinary
-- version deletion remains denied by the existing lifecycle guard.
CREATE FUNCTION public.delete_note_quote_locator_for_purged_version()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.trash_purge_execution_fences AS fence
    WHERE fence.transaction_id = txid_current()
  ) THEN
    RAISE EXCEPTION 'note quotation sources require the governed Trash purge';
  END IF;
  DELETE FROM public.note_document_quotes AS quote
  WHERE quote.org_id = OLD.org_id AND quote.document_version_id = OLD.id;
  RETURN OLD;
END $$;
CREATE TRIGGER note_quote_locator_version_purge_order
  BEFORE DELETE ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.delete_note_quote_locator_for_purged_version();
REVOKE ALL ON FUNCTION public.delete_note_quote_locator_for_purged_version() FROM PUBLIC, anon, authenticated, service_role;

-- This narrow authenticated projection never returns storage locators. It
-- reports whether the exact immutable source remains readable, but never
-- substitutes the document's current version for a missing locator.
CREATE FUNCTION public.get_note_quote_locators(p_note_ids uuid[], p_trash_matter_id uuid DEFAULT NULL)
RETURNS TABLE(
  note_id uuid,
  document_id uuid,
  document_version_id uuid,
  page_number integer,
  excerpt text,
  version_number integer,
  is_current boolean,
  source_available boolean
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
DECLARE v_org uuid;
BEGIN
  IF p_note_ids IS NULL OR cardinality(p_note_ids) = 0 OR cardinality(p_note_ids) > 500 THEN RETURN; END IF;
  SELECT membership.org_id INTO v_org FROM public.current_active_tenant_membership() AS membership;
  IF v_org IS NULL THEN RETURN; END IF;
  RETURN QUERY
  SELECT quote.note_id, quote.document_id, quote.document_version_id, quote.page_number,
    quote.excerpt, version.version_number,
    document.current_version_id = quote.document_version_id,
    version.id IS NOT NULL
      AND version.state IN ('current','superseded')
      AND version.validation_state = 'valid'
      AND version.page_count IS NOT NULL
      AND quote.page_number <= version.page_count
      AND asset.availability = 'available'
      AND asset.storage_deleted_at IS NULL
      AND (
        (document.record_state='active' AND document.deleted_at IS NULL)
        OR (
          p_trash_matter_id=quote.matter_id
          AND EXISTS (
            SELECT 1 FROM public.resource_trash_memberships AS membership
            JOIN public.trash_operations AS operation
              ON operation.org_id=membership.org_id AND operation.id=membership.operation_id
            WHERE membership.org_id=quote.org_id
              AND membership.resource_type='document'
              AND membership.resource_id=quote.document_id
              AND membership.state='active'
              AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
          )
        )
      )
  FROM public.note_document_quotes AS quote
  JOIN public.case_notes AS note
    ON note.org_id=quote.org_id AND note.matter_id=quote.matter_id AND note.id=quote.note_id
  LEFT JOIN public.documents AS document
    ON document.org_id=quote.org_id AND document.matter_id=quote.matter_id AND document.id=quote.document_id
  LEFT JOIN public.document_versions AS version
    ON version.org_id=quote.org_id AND version.document_id=quote.document_id AND version.id=quote.document_version_id
  LEFT JOIN public.file_assets AS asset
    ON asset.org_id=version.org_id AND asset.id=version.asset_id
  WHERE quote.org_id=v_org AND quote.note_id=ANY(p_note_ids) AND note.deleted_at IS NULL;
END $$;
REVOKE ALL ON FUNCTION public.get_note_quote_locators(uuid[],uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_note_quote_locators(uuid[],uuid) TO authenticated;

DROP FUNCTION public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer);
CREATE FUNCTION public.create_note_with_optional_task(
  p_matter_id uuid,p_content text,p_template_type public.note_template_type,p_is_action_item boolean,p_idempotency_key uuid,
  p_document_id uuid DEFAULT NULL,p_action_item_assignee uuid DEFAULT NULL,p_action_item_due_date date DEFAULT NULL,
  p_parent_note_id uuid DEFAULT NULL,p_quote text DEFAULT NULL,p_page_number integer DEFAULT NULL,
  p_document_version_id uuid DEFAULT NULL
) RETURNS TABLE(code text,note_id uuid,task_id uuid,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_org uuid; v_actor_role public.org_member_role; v_client uuid;
  v_note public.case_notes%ROWTYPE; v_task uuid; v_receipt public.task_command_receipts%ROWTYPE;
  v_parent public.case_notes%ROWTYPE; v_version public.document_versions%ROWTYPE; v_asset public.file_assets%ROWTYPE;
  v_timezone text; v_fingerprint text; v_title text; v_activity_idempotency_key text;
  v_current_count integer:=0; v_active_count integer:=0; v_locked_membership public.organisation_memberships%ROWTYPE;
  v_has_quote boolean:=false;
BEGIN
  v_has_quote := p_quote IS NOT NULL OR p_page_number IS NOT NULL OR p_document_version_id IS NOT NULL;
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR p_matter_id IS NULL OR p_content IS NULL
     OR btrim(p_content)='' OR char_length(p_content)>20000 OR p_template_type IS NULL OR p_is_action_item IS NULL
     OR (v_has_quote AND (p_document_id IS NULL OR p_quote IS NULL OR btrim(p_quote)='' OR char_length(p_quote)>20000
       OR p_page_number IS NULL OR p_page_number<1 OR p_document_version_id IS NULL)) THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,95));
  FOR v_locked_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_locked_membership.state='active' THEN
      v_active_count:=v_active_count+1; v_org:=v_locked_membership.org_id; v_actor_role:=v_locked_membership.role;
    END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_actor_role='viewer' THEN
    IF v_current_count>1 THEN RAISE LOG 'organisation membership invariant violation during Note creation for actor %: % current memberships',v_actor,v_current_count; END IF;
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,false; RETURN;
  END IF;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'matter_id',p_matter_id,'document_id',p_document_id,'document_version_id',p_document_version_id,
    'content',p_content,'template_type',p_template_type::text,'is_action_item',p_is_action_item,
    'action_item_assignee',p_action_item_assignee,'action_item_due_date',p_action_item_due_date,
    'parent_note_id',p_parent_note_id,'quote',p_quote,'page_number',p_page_number
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.task_command_receipts WHERE idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_org OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::uuid,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.note_id,v_receipt.task_id,true; END IF;
    RETURN;
  END IF;

  -- Keep note creation in the same organisation hierarchy fence as Trash.
  -- This is deliberately after a verified replay: a completed command may
  -- return its durable result without revalidating a source later removed.
  -- New writes take the fence before locking hierarchy rows, matching Trash's
  -- advisory-before-row-lock order.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(v_org::text),
    pg_catalog.hashtext('hierarchical-resource-trash')
  );

  SELECT matter.client_id INTO v_client
  FROM public.matters AS matter
  JOIN public.clients AS client ON client.id=matter.client_id AND client.org_id=matter.org_id
  WHERE matter.id=p_matter_id AND matter.org_id=v_org
    AND matter.record_state='active' AND matter.deleted_at IS NULL
    AND client.record_state='active' AND client.deleted_at IS NULL
  FOR SHARE OF matter,client;
  IF v_client IS NULL THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;

  IF p_document_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.documents AS document
    WHERE document.id=p_document_id AND document.org_id=v_org AND document.matter_id=p_matter_id
      AND document.record_state='active' AND document.deleted_at IS NULL FOR SHARE
  ) THEN RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;

  IF v_has_quote THEN
    SELECT version.* INTO v_version FROM public.document_versions AS version
    WHERE version.id=p_document_version_id AND version.org_id=v_org AND version.document_id=p_document_id FOR SHARE;
    IF v_version.id IS NULL OR v_version.state NOT IN ('current','superseded') OR v_version.validation_state<>'valid'
       OR v_version.page_count IS NULL OR p_page_number>v_version.page_count THEN
      RETURN QUERY SELECT 'source_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN;
    END IF;
    SELECT asset.* INTO v_asset FROM public.file_assets AS asset
    WHERE asset.id=v_version.asset_id AND asset.org_id=v_org FOR SHARE;
    IF v_asset.id IS NULL OR v_asset.availability<>'available' OR v_asset.storage_deleted_at IS NOT NULL THEN
      RETURN QUERY SELECT 'source_unavailable'::text,NULL::uuid,NULL::uuid,false; RETURN;
    END IF;
  END IF;

  IF p_parent_note_id IS NOT NULL THEN
    SELECT * INTO v_parent FROM public.case_notes AS parent_note
    WHERE parent_note.id=p_parent_note_id AND parent_note.org_id=v_org AND parent_note.matter_id=p_matter_id
      AND parent_note.deleted_at IS NULL FOR SHARE;
    IF v_parent.id IS NULL OR (p_document_id IS NOT NULL AND v_parent.document_id IS DISTINCT FROM p_document_id) THEN
      RETURN QUERY SELECT 'invalid_parent_note'::text,NULL::uuid,NULL::uuid,false; RETURN;
    END IF;
  END IF;
  IF p_is_action_item AND p_action_item_assignee IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.organisation_memberships AS assignee
    WHERE assignee.org_id=v_org AND assignee.user_id=p_action_item_assignee AND assignee.state='active'
      AND assignee.role IN ('admin','associate')
  ) THEN RETURN QUERY SELECT 'invalid_assignee'::text,NULL::uuid,NULL::uuid,false; RETURN; END IF;
  IF NOT p_is_action_item AND (p_action_item_assignee IS NOT NULL OR p_action_item_due_date IS NOT NULL) THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,false; RETURN;
  END IF;
  IF p_is_action_item THEN
    SELECT settings.timezone INTO v_timezone FROM public.organisation_operational_settings AS settings
    WHERE settings.org_id=v_org FOR KEY SHARE;
    IF v_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=v_timezone) THEN
      RETURN QUERY SELECT 'invalid_timezone'::text,NULL::uuid,NULL::uuid,false; RETURN;
    END IF;
  END IF;

  INSERT INTO public.case_notes(
    org_id,author_id,matter_id,document_id,content,template_type,is_action_item,
    action_item_assignee,action_item_due_date,parent_note_id,quote,page_number,is_pinned,action_item_resolved
  ) VALUES(
    v_org,v_actor,p_matter_id,p_document_id,p_content,p_template_type,p_is_action_item,
    CASE WHEN p_is_action_item THEN p_action_item_assignee ELSE NULL END,
    CASE WHEN p_is_action_item THEN p_action_item_due_date ELSE NULL END,
    p_parent_note_id,p_quote,p_page_number,false,false
  ) RETURNING * INTO v_note;
  IF v_has_quote THEN
    INSERT INTO public.note_document_quotes(
      note_id,org_id,matter_id,document_id,document_version_id,page_number,excerpt,selection_method
    ) VALUES(v_note.id,v_org,p_matter_id,p_document_id,p_document_version_id,p_page_number,p_quote,'text');
  END IF;
  IF p_is_action_item THEN
    v_title:=left(regexp_replace(btrim(p_content),'[[:space:]]+',' ','g'),240);
    INSERT INTO public.tasks(
      org_id,client_id,matter_id,document_id,title,description,origin_kind,origin_note_id,origin_snapshot,
      creator_user_id,assignee_user_id,priority,status,due_date,due_time,due_timezone,revision,lifecycle_state,status_changed_by
    ) VALUES(
      v_org,v_client,p_matter_id,p_document_id,v_title,NULL,'case_note',v_note.id,p_content,
      v_actor,p_action_item_assignee,'normal','open',p_action_item_due_date,NULL,
      CASE WHEN p_action_item_due_date IS NULL THEN NULL ELSE v_timezone END,1,'active',v_actor
    ) RETURNING id INTO v_task;
  END IF;
  INSERT INTO public.task_command_receipts(org_id,actor_user_id,idempotency_key,request_fingerprint,note_id,task_id)
  VALUES(v_org,v_actor,p_idempotency_key,v_fingerprint,v_note.id,v_task);
  IF v_task IS NOT NULL THEN
    v_activity_idempotency_key:=encode(extensions.digest(convert_to(jsonb_build_object(
      'command','task.created','task_id',v_task,'command_idempotency_key',p_idempotency_key,
      'org_id',v_org,'actor_id',v_actor
    )::text,'utf8'),'sha256'),'hex');
    PERFORM public.append_activity_event(v_org,'task.created',1::smallint,'user',v_actor,NULL,'task',v_task,
      v_client,p_matter_id,'Task','Task created','{}'::jsonb,'task',v_task,NULL,p_idempotency_key,NULL,
      v_activity_idempotency_key,now());
  END IF;
  RETURN QUERY SELECT 'ok'::text,v_note.id,v_task,false;
END $$;

REVOKE ALL ON FUNCTION public.create_note_with_optional_task(
  uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer,uuid
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_note_with_optional_task(
  uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer,uuid
) TO authenticated;

COMMENT ON TABLE public.note_document_quotes IS
  'One authoritative immutable document-version/page locator for the enabled legacy case_notes adapter. Ambiguous legacy quote/page columns are never backfilled.';
COMMENT ON FUNCTION public.create_note_with_optional_task(
  uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer,uuid
) IS 'Atomic Note/optional Task writer with locked active membership and exact immutable quotation validation.';

COMMIT;
