-- Logical document materialisation and immutable-version commands.
BEGIN;

-- Metadata-only records have no physical-file fiction.  The legacy columns
-- remain in place for the compatibility window, but are no longer required.
ALTER TABLE public.documents
  ADD COLUMN display_title text,
  ALTER COLUMN storage_path DROP NOT NULL,
  ADD CONSTRAINT documents_display_title_safe CHECK (
    display_title IS NULL OR (char_length(display_title) BETWEEN 1 AND 255 AND display_title !~ '[[:cntrl:]]')
  );

ALTER TABLE public.file_assets
  ADD COLUMN validated_page_count integer,
  ADD CONSTRAINT file_assets_validated_page_count_positive CHECK (validated_page_count IS NULL OR validated_page_count > 0);

CREATE TABLE public.document_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  command_kind text NOT NULL CHECK (command_kind IN ('validate_asset','create_metadata','assign_intake','attach_intake','replace_version')),
  idempotency_key uuid NOT NULL,
  subject_id uuid NOT NULL,
  result_code text NOT NULL CHECK (result_code ~ '^[a-z][a-z0-9_]{0,63}$'),
  document_id uuid REFERENCES public.documents(id) ON DELETE RESTRICT,
  document_version_id uuid REFERENCES public.document_versions(id) ON DELETE RESTRICT,
  lifecycle_revision bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (org_id, actor_user_id, command_kind, idempotency_key)
);
CREATE UNIQUE INDEX document_command_receipts_null_actor_unique
  ON public.document_command_receipts(org_id, command_kind, idempotency_key)
  WHERE actor_user_id IS NULL;
ALTER TABLE public.document_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_command_receipts FORCE ROW LEVEL SECURITY;

-- Extend the one central capability projection; consumers of the projection
-- (including the existing team-member projection) inherit this exact matrix.
CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 SELECT m.id,m.org_id,m.role,(o.owner_membership_id=m.id),m.state,3,
   CASE WHEN m.state <> 'active' THEN ARRAY[]::text[]
   WHEN o.owner_membership_id=m.id THEN ARRAY['team.view','team.invite.standard','team.role.manage_standard','team.membership.suspend_standard','organisation.profile.manage','organisation.operations.manage','team.invite.admin','team.role.manage_admin','team.membership.manage_admin','team.ownership.transfer','trash.purge','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
   WHEN m.role='admin' THEN ARRAY['team.view','team.invite.standard','team.role.manage_standard','team.membership.suspend_standard','organisation.profile.manage','organisation.operations.manage','trash.purge','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
   WHEN m.role='associate' THEN ARRAY['team.view','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
   ELSE ARRAY['team.view','document.view']::text[] END,m.revision
 FROM public.organisation_memberships m JOIN public.organisations o ON o.id=m.org_id
 WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended');
$$;

-- The member projection intentionally mirrors the central matrix for the
-- member being described; it must not leak a caller's elevated capabilities.
CREATE OR REPLACE FUNCTION public.get_my_team_members()
RETURNS TABLE (membership_id uuid, display_name text, professional_title text, role public.org_member_role, is_owner boolean, state public.organisation_membership_state, joined_at timestamptz, revision bigint, capabilities text[], authorised_email text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 WITH caller AS (
   SELECT c.org_id,c.is_owner,c.role FROM public.get_my_organisation_context() c
   WHERE c.state='active' AND 'team.view'=ANY(c.capabilities)
 )
 SELECT m.id,p.display_name,p.professional_title,m.role,(o.owner_membership_id=m.id),m.state,m.joined_at,m.revision,
   CASE WHEN m.state<>'active' THEN ARRAY[]::text[]
     WHEN o.owner_membership_id=m.id THEN ARRAY['team.view','team.invite.standard','team.role.manage_standard','team.membership.suspend_standard','organisation.profile.manage','organisation.operations.manage','team.invite.admin','team.role.manage_admin','team.membership.manage_admin','team.ownership.transfer','trash.purge','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
     WHEN m.role='admin' THEN ARRAY['team.view','team.invite.standard','team.role.manage_standard','team.membership.suspend_standard','organisation.profile.manage','organisation.operations.manage','trash.purge','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
     WHEN m.role='associate' THEN ARRAY['team.view','document.view','document.intake.create','document.record.create','document.intake.assign','document.version.attach','document.version.replace']::text[]
     ELSE ARRAY['team.view','document.view']::text[] END,
   CASE WHEN (c.is_owner OR c.role='admin' OR m.user_id=auth.uid()) AND u.email_confirmed_at IS NOT NULL THEN u.email END
 FROM caller c JOIN public.organisation_memberships m ON m.org_id=c.org_id
 JOIN public.organisations o ON o.id=m.org_id
 LEFT JOIN public.user_profiles p ON p.user_id=m.user_id
 LEFT JOIN auth.users u ON u.id=m.user_id
 WHERE m.state='active' OR (m.state='suspended' AND (c.is_owner OR c.role='admin'));
$$;

CREATE OR REPLACE FUNCTION public.document_materialization_safe_event(p_org uuid,p_aggregate uuid,p_kind text,p_key text,p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES (p_org,'document',p_aggregate,p_kind,p_payload,p_key)
  ON CONFLICT (org_id,idempotency_key) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.document_materialization_actor(p_capability text)
RETURNS TABLE(org_id uuid, actor_id uuid) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
 SELECT c.org_id, auth.uid() FROM public.get_my_organisation_context() c
 WHERE c.state='active' AND p_capability=ANY(c.capabilities) AND auth.uid() IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.document_materialization_insert_version(
  p_org uuid, p_document uuid, p_intake uuid, p_actor uuid, p_reason text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_intake public.intake_items%ROWTYPE; v_asset public.file_assets%ROWTYPE;
  v_name text; v_number integer; v_version uuid;
BEGIN
  SELECT * INTO v_intake FROM public.intake_items WHERE id=p_intake AND org_id=p_org FOR UPDATE;
  SELECT * INTO v_asset FROM public.file_assets WHERE id=v_intake.asset_id AND org_id=p_org FOR UPDATE;
  IF v_intake.id IS NULL OR v_intake.state<>'ready' OR v_asset.id IS NULL OR v_asset.availability<>'available'
     OR v_asset.detected_mime_type<>'application/pdf' OR v_asset.validated_page_count IS NULL THEN
    RAISE EXCEPTION 'intake is not a ready validated PDF';
  END IF;
  SELECT declared_filename INTO v_name FROM public.upload_sessions
    WHERE id=v_intake.upload_session_id AND org_id=p_org;
  IF v_name IS NULL THEN RAISE EXCEPTION 'trusted upload filename is unavailable'; END IF;
  SELECT coalesce(max(version_number),0)+1 INTO v_number FROM public.document_versions
    WHERE document_id=p_document;
  INSERT INTO public.document_versions AS document_version (org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,replacement_reason,created_by,validated_at,promoted_at)
  VALUES(p_org,p_document,v_asset.id,v_number,v_name,v_asset.validated_page_count,'valid','current',p_reason,p_actor,now(),now()) RETURNING document_version.id INTO v_version;
  RETURN v_version;
END $$;

CREATE OR REPLACE FUNCTION public.validate_document_intake_asset(p_intake_id uuid,p_page_count integer,p_outcome text,p_idempotency uuid)
RETURNS TABLE(code text, intake_item_id uuid, asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE i public.intake_items%ROWTYPE; a public.file_assets%ROWTYPE; r public.document_command_receipts%ROWTYPE; v_code text;
BEGIN
  IF p_idempotency IS NULL OR p_outcome NOT IN ('ready','invalid_pdf','encrypted_pdf','malware_suspect','storage_missing','validation_failed') THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id FOR UPDATE;
  IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid; RETURN; END IF;
  SELECT * INTO r FROM public.document_command_receipts WHERE org_id=i.org_id AND actor_user_id IS NULL AND command_kind='validate_asset' AND idempotency_key=p_idempotency;
  IF r.id IS NOT NULL THEN RETURN QUERY SELECT r.result_code,i.id,i.asset_id; RETURN; END IF;
  SELECT * INTO a FROM public.file_assets WHERE id=i.asset_id FOR UPDATE;
  IF i.state='ready' AND a.availability='available' THEN v_code:='already_ready';
  ELSIF i.state NOT IN ('uploaded','validating','processing') OR a.availability NOT IN ('available','uploaded','validating') THEN v_code:='not_available';
  ELSIF p_outcome='ready' AND p_page_count IS NOT NULL AND p_page_count>0 AND a.detected_mime_type='application/pdf' THEN
    UPDATE public.file_assets SET availability='available',validated_at=coalesce(validated_at,now()),validated_page_count=p_page_count WHERE id=a.id;
    UPDATE public.intake_items SET state='ready',updated_at=now(),failure_code=NULL WHERE id=i.id;
    v_code:='ok';
  ELSE
    v_code:=CASE WHEN p_outcome='ready' THEN 'invalid_pdf' ELSE p_outcome END;
    UPDATE public.file_assets SET availability=CASE WHEN v_code IN ('storage_missing','validation_failed') THEN 'failed'::public.file_asset_availability ELSE 'quarantined'::public.file_asset_availability END,
      validated_at=NULL, failed_at=CASE WHEN v_code IN ('storage_missing','validation_failed') THEN now() ELSE NULL END, failure_code=v_code WHERE id=a.id;
    UPDATE public.intake_items SET state='failed',failed_at=now(),updated_at=now(),failure_code=v_code WHERE id=i.id;
  END IF;
  INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code)
  VALUES(i.org_id,NULL,'validate_asset',p_idempotency,i.id,v_code);
  PERFORM public.document_materialization_safe_event(i.org_id,i.id,CASE WHEN v_code IN ('ok','already_ready') THEN 'document.intake_validated.v1' ELSE 'document.intake_validation_failed.v1' END,
    'document.intake.validate.'||i.id::text,jsonb_build_object('intake_id',i.id::text,'asset_id',i.asset_id::text,'result_code',v_code));
  RETURN QUERY SELECT v_code,i.id,i.asset_id;
END $$;

CREATE OR REPLACE FUNCTION public.create_metadata_only_document(p_matter_id uuid,p_display_title text,p_doc_type text,p_reference_number text,p_doc_date date,p_idempotency uuid)
RETURNS TABLE(code text, document_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; d uuid; rev bigint; prior public.document_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO x FROM public.document_materialization_actor('document.record.create') LIMIT 1;
 IF x.org_id IS NULL OR p_idempotency IS NULL OR p_display_title IS NULL OR char_length(p_display_title) NOT BETWEEN 1 AND 255 OR p_display_title ~ '[[:cntrl:]]' OR (p_doc_type IS NOT NULL AND (char_length(p_doc_type)>120 OR p_doc_type~'[[:cntrl:]]')) OR (p_reference_number IS NOT NULL AND (char_length(p_reference_number)>160 OR p_reference_number~'[[:cntrl:]]')) THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='create_metadata' AND idempotency_key=p_idempotency;
 IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_id,prior.lifecycle_revision; RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=p_matter_id AND m.org_id=x.org_id AND m.status='active' AND m.deleted_at IS NULL) THEN RETURN QUERY SELECT 'invalid_matter'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 INSERT INTO public.documents AS document_record (org_id,matter_id,display_title,doc_type,reference_number,doc_date,origin_kind,record_state,content_availability,status,storage_path,created_by)
 VALUES(x.org_id,p_matter_id,p_display_title,p_doc_type,p_reference_number,p_doc_date,'manual_record','active','metadata_only','placed',NULL,x.actor_id) RETURNING document_record.id,document_record.lifecycle_revision INTO d,rev;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.metadata_created','document',d,'Created a metadata-only document record',jsonb_build_object('document_id',d::text));
 INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'create_metadata',p_idempotency,p_matter_id,'ok',d,rev);
 PERFORM public.document_materialization_safe_event(x.org_id,d,'document.metadata_created.v1','document.metadata.create.'||d::text,jsonb_build_object('document_id',d::text,'matter_id',p_matter_id::text));
 RETURN QUERY SELECT 'ok'::text,d,rev;
END $$;

CREATE OR REPLACE FUNCTION public.assign_intake_to_new_document(p_intake_id uuid,p_matter_id uuid,p_display_title text,p_expected_intake_uploader uuid,p_idempotency uuid)
RETURNS TABLE(code text, document_id uuid, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; i public.intake_items%ROWTYPE; d uuid; v uuid; rev bigint; prior public.document_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO x FROM public.document_materialization_actor('document.intake.assign') LIMIT 1;
 IF x.org_id IS NULL OR p_idempotency IS NULL OR p_display_title IS NULL OR char_length(p_display_title) NOT BETWEEN 1 AND 255 OR p_display_title~'[[:cntrl:]]' THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='assign_intake' AND idempotency_key=p_idempotency;
 IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_id,prior.document_version_id,prior.lifecycle_revision; RETURN; END IF;
 SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
 IF i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.uploaded_by IS NULL THEN RETURN QUERY SELECT 'uploader_mismatch'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=p_matter_id AND m.org_id=x.org_id AND m.status='active' AND m.deleted_at IS NULL) THEN RETURN QUERY SELECT 'invalid_matter'::text,NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
 INSERT INTO public.documents AS document_record (org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,storage_path,created_by) VALUES(x.org_id,p_matter_id,p_display_title,'upload','active','metadata_only','placed',NULL,x.actor_id) RETURNING document_record.id INTO d;
 v:=public.document_materialization_insert_version(x.org_id,d,i.id,x.actor_id,NULL);
 UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions AS dv WHERE dv.id=v),effective_size_bytes=(SELECT asset.byte_size FROM public.file_assets AS asset JOIN public.document_versions AS dv ON dv.asset_id=asset.id WHERE dv.id=v) WHERE document_record.id=d RETURNING document_record.lifecycle_revision INTO rev;
 INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d,v,x.actor_id); UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.intake_assigned','document',d,'Assigned validated intake to a new document',jsonb_build_object('document_id',d::text,'version_id',v::text));
 INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'assign_intake',p_idempotency,i.id,'ok',d,v,rev);
 PERFORM public.document_materialization_safe_event(x.org_id,d,'document.processing_requested.v1','document.processing.assign.'||v::text,jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text));
 RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

CREATE OR REPLACE FUNCTION public.attach_intake_to_document(p_document_id uuid,p_intake_id uuid,p_expected_revision bigint,p_expected_intake_uploader uuid,p_idempotency uuid)
RETURNS TABLE(code text, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; d public.documents%ROWTYPE; i public.intake_items%ROWTYPE; v uuid; rev bigint; prior public.document_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO x FROM public.document_materialization_actor('document.version.attach') LIMIT 1;
 IF x.org_id IS NULL OR p_idempotency IS NULL THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='attach_intake' AND idempotency_key=p_idempotency; IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_version_id,prior.lifecycle_revision; RETURN; END IF;
 SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE; SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
 IF d.id IS NULL OR i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF d.record_state<>'active' THEN RETURN QUERY SELECT 'record_trashed'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF d.lifecycle_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision'::text,NULL::uuid,d.lifecycle_revision; RETURN; END IF;
 IF d.content_availability<>'metadata_only' OR d.current_version_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id) THEN RETURN QUERY SELECT 'document_not_metadata_only'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,NULL); UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions AS dv WHERE dv.id=v),effective_size_bytes=(SELECT asset.byte_size FROM public.file_assets AS asset JOIN public.document_versions AS dv ON dv.asset_id=asset.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
 INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id); UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.file_attached','document',d.id,'Attached validated source to document',jsonb_build_object('document_id',d.id::text,'version_id',v::text)); INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'attach_intake',p_idempotency,d.id,'ok',d.id,v,rev);
 PERFORM public.document_materialization_safe_event(x.org_id,d.id,'document.processing_requested.v1','document.processing.attach.'||v::text,jsonb_build_object('document_id',d.id::text,'version_id',v::text,'intake_id',i.id::text)); RETURN QUERY SELECT 'ok'::text,v,rev;
END $$;

CREATE OR REPLACE FUNCTION public.replace_document_version(p_document_id uuid,p_intake_id uuid,p_expected_revision bigint,p_replacement_reason text,p_expected_intake_uploader uuid,p_idempotency uuid)
RETURNS TABLE(code text, document_version_id uuid, lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; d public.documents%ROWTYPE; i public.intake_items%ROWTYPE; old public.document_versions%ROWTYPE; v uuid; rev bigint; prior public.document_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO x FROM public.document_materialization_actor('document.version.replace') LIMIT 1;
 IF x.org_id IS NULL OR p_idempotency IS NULL OR p_replacement_reason IS NULL OR char_length(btrim(p_replacement_reason)) NOT BETWEEN 1 AND 500 OR p_replacement_reason~'[[:cntrl:]]' THEN RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 SELECT * INTO prior FROM public.document_command_receipts WHERE org_id=x.org_id AND actor_user_id=x.actor_id AND command_kind='replace_version' AND idempotency_key=p_idempotency; IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.result_code,prior.document_version_id,prior.lifecycle_revision; RETURN; END IF;
 SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=x.org_id FOR UPDATE; SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
 IF d.id IS NULL OR i.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::bigint; RETURN; END IF; IF d.record_state<>'active' THEN RETURN QUERY SELECT 'record_trashed'::text,NULL::uuid,NULL::bigint; RETURN; END IF; IF d.lifecycle_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision'::text,NULL::uuid,d.lifecycle_revision; RETURN; END IF;
 SELECT * INTO old FROM public.document_versions WHERE id=d.current_version_id AND document_id=d.id FOR UPDATE; IF old.id IS NULL OR i.state<>'ready' OR i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR EXISTS(SELECT 1 FROM public.intake_item_assignments ia WHERE ia.intake_item_id=i.id) THEN RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 IF old.asset_id=(SELECT asset_id FROM public.intake_items WHERE id=i.id) THEN RETURN QUERY SELECT 'same_asset'::text,NULL::uuid,NULL::bigint; RETURN; END IF;
 UPDATE public.document_versions AS prior_version SET state='superseded',superseded_at=now() WHERE prior_version.id=old.id; v:=public.document_materialization_insert_version(x.org_id,d.id,i.id,x.actor_id,btrim(p_replacement_reason)); UPDATE public.documents AS document_record SET current_version_id=v,content_availability='source_attached',effective_filename=(SELECT dv.original_filename FROM public.document_versions AS dv WHERE dv.id=v),effective_size_bytes=(SELECT asset.byte_size FROM public.file_assets AS asset JOIN public.document_versions AS dv ON dv.asset_id=asset.id WHERE dv.id=v) WHERE document_record.id=d.id RETURNING document_record.lifecycle_revision INTO rev;
 INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(x.org_id,i.id,d.id,v,x.actor_id); UPDATE public.intake_items SET state='assigned',assigned_at=now(),updated_at=now() WHERE id=i.id;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata) VALUES(x.org_id,x.actor_id,'document.version_replaced','document',d.id,'Replaced document source version',jsonb_build_object('document_id',d.id::text,'version_id',v::text)); INSERT INTO public.document_command_receipts(org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,document_id,document_version_id,lifecycle_revision) VALUES(x.org_id,x.actor_id,'replace_version',p_idempotency,d.id,'ok',d.id,v,rev); PERFORM public.document_materialization_safe_event(x.org_id,d.id,'document.processing_requested.v1','document.processing.replace.'||v::text,jsonb_build_object('document_id',d.id::text,'version_id',v::text,'intake_id',i.id::text)); RETURN QUERY SELECT 'ok'::text,v,rev;
END $$;

CREATE VIEW public.document_materialization_diagnostics AS
 SELECT d.org_id,d.id AS document_id,'metadata_only_has_file_projection'::text AS issue FROM public.documents d WHERE d.content_availability='metadata_only' AND (d.current_version_id IS NOT NULL OR d.storage_path IS NOT NULL OR d.effective_filename IS NOT NULL OR d.effective_size_bytes IS NOT NULL OR d.file_hash_sha256 IS NOT NULL OR d.content_hash IS NOT NULL OR d.embedding IS NOT NULL)
 UNION ALL SELECT d.org_id,d.id,'attached_missing_current_version' FROM public.documents d LEFT JOIN public.document_versions v ON v.id=d.current_version_id WHERE d.origin_kind<>'legacy_migration' AND d.content_availability<>'metadata_only' AND (v.id IS NULL OR v.state<>'current')
 UNION ALL SELECT ia.org_id,ia.document_id,'assignment_not_assigned' FROM public.intake_item_assignments ia JOIN public.intake_items i ON i.id=ia.intake_item_id WHERE i.state<>'assigned' OR i.asset_id<>(SELECT asset_id FROM public.document_versions WHERE id=ia.document_version_id);

ALTER TABLE public.document_command_receipts ENABLE ROW LEVEL SECURITY; ALTER TABLE public.document_command_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_command_receipts, public.document_materialization_diagnostics FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT,INSERT ON public.document_command_receipts TO service_role;
GRANT SELECT ON public.document_materialization_diagnostics TO service_role, postgres;
REVOKE ALL ON FUNCTION public.document_materialization_safe_event(uuid,uuid,text,text,jsonb), public.document_materialization_actor(text), public.document_materialization_insert_version(uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_document_intake_asset(uuid,integer,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_metadata_only_document(uuid,text,text,text,date,uuid), public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid), public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid), public.replace_document_version(uuid,uuid,bigint,text,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.validate_document_intake_asset(uuid,integer,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_metadata_only_document(uuid,text,text,text,date,uuid), public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid), public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid), public.replace_document_version(uuid,uuid,bigint,text,uuid,uuid) TO authenticated;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM public.document_materialization_diagnostics) THEN RAISE EXCEPTION 'document materialization diagnostics are not clean'; END IF; END $$;
COMMIT;
