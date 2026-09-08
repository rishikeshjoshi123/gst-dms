-- Additive Matter work-state/forum normalization and governed typed commands.
BEGIN;

CREATE TYPE public.matter_work_state AS ENUM ('active', 'stayed', 'disposed', 'closed');
CREATE TYPE public.matter_current_forum AS ENUM (
  'adjudication', 'first_appeal', 'tribunal', 'high_court',
  'supreme_court', 'remand', 'other'
);

ALTER TABLE public.matters
  ADD COLUMN work_state public.matter_work_state,
  ADD COLUMN current_forum public.matter_current_forum;

-- This append-only migration report makes closed ambiguity and every source
-- mapping inspectable without using documents or other inferred evidence.
CREATE TABLE public.matter_status_normalization_report (
  matter_id uuid PRIMARY KEY,
  org_id uuid NOT NULL,
  legacy_status text NOT NULL,
  mapped_work_state public.matter_work_state,
  mapped_current_forum public.matter_current_forum,
  disposition text NOT NULL CHECK (disposition IN ('mapped', 'ambiguous_closed', 'unmapped')),
  record_state public.resource_record_state NOT NULL,
  reported_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.matter_status_normalization_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_status_normalization_report FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.matter_status_normalization_report FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO public.matter_status_normalization_report(
  matter_id, org_id, legacy_status, mapped_work_state, mapped_current_forum, disposition, record_state
)
SELECT matter.id, matter.org_id, matter.status::text,
  CASE matter.status
    WHEN 'stayed' THEN 'stayed'::public.matter_work_state
    WHEN 'disposed' THEN 'disposed'::public.matter_work_state
    WHEN 'closed' THEN 'closed'::public.matter_work_state
    WHEN 'active' THEN 'active'::public.matter_work_state
    WHEN 'appeal_pending' THEN 'active'::public.matter_work_state
    WHEN 'tribunal' THEN 'active'::public.matter_work_state
    WHEN 'high_court' THEN 'active'::public.matter_work_state
    WHEN 'supreme_court' THEN 'active'::public.matter_work_state
    ELSE NULL
  END,
  CASE matter.status
    WHEN 'appeal_pending' THEN 'first_appeal'::public.matter_current_forum
    WHEN 'tribunal' THEN 'tribunal'::public.matter_current_forum
    WHEN 'high_court' THEN 'high_court'::public.matter_current_forum
    WHEN 'supreme_court' THEN 'supreme_court'::public.matter_current_forum
    WHEN 'closed' THEN 'other'::public.matter_current_forum
    WHEN 'active' THEN 'adjudication'::public.matter_current_forum
    WHEN 'stayed' THEN 'adjudication'::public.matter_current_forum
    WHEN 'disposed' THEN 'adjudication'::public.matter_current_forum
    ELSE NULL
  END,
  CASE WHEN matter.status='closed' THEN 'ambiguous_closed' ELSE 'mapped' END,
  matter.record_state
FROM public.matters AS matter;

DO $backfill_complete$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.matter_status_normalization_report
    WHERE disposition='unmapped' OR mapped_work_state IS NULL OR mapped_current_forum IS NULL
  ) THEN
    RAISE EXCEPTION 'Matter status normalization has unmapped rows';
  END IF;
END $backfill_complete$;

UPDATE public.matters AS matter
SET work_state=report.mapped_work_state,
    current_forum=report.mapped_current_forum
FROM public.matter_status_normalization_report AS report
WHERE report.matter_id=matter.id AND report.org_id=matter.org_id;

ALTER TABLE public.matters
  ALTER COLUMN work_state SET DEFAULT 'active'::public.matter_work_state,
  ALTER COLUMN work_state SET NOT NULL,
  ALTER COLUMN current_forum SET DEFAULT 'adjudication'::public.matter_current_forum,
  ALTER COLUMN current_forum SET NOT NULL;

CREATE OR REPLACE FUNCTION public.matter_work_state_from_legacy(p_status public.matter_status)
RETURNS public.matter_work_state LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE p_status
    WHEN 'stayed' THEN 'stayed'::public.matter_work_state
    WHEN 'disposed' THEN 'disposed'::public.matter_work_state
    WHEN 'closed' THEN 'closed'::public.matter_work_state
    ELSE 'active'::public.matter_work_state
  END
$$;

CREATE OR REPLACE FUNCTION public.matter_current_forum_from_legacy(p_status public.matter_status)
RETURNS public.matter_current_forum LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE p_status
    WHEN 'appeal_pending' THEN 'first_appeal'::public.matter_current_forum
    WHEN 'tribunal' THEN 'tribunal'::public.matter_current_forum
    WHEN 'high_court' THEN 'high_court'::public.matter_current_forum
    WHEN 'supreme_court' THEN 'supreme_court'::public.matter_current_forum
    WHEN 'closed' THEN 'other'::public.matter_current_forum
    ELSE 'adjudication'::public.matter_current_forum
  END
$$;

CREATE OR REPLACE FUNCTION public.matter_legacy_status(
  p_work_state public.matter_work_state,
  p_current_forum public.matter_current_forum
) RETURNS public.matter_status LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE
    WHEN p_work_state='stayed' THEN 'stayed'::public.matter_status
    WHEN p_work_state='disposed' THEN 'disposed'::public.matter_status
    WHEN p_work_state='closed' THEN 'closed'::public.matter_status
    WHEN p_current_forum='first_appeal' THEN 'appeal_pending'::public.matter_status
    WHEN p_current_forum='tribunal' THEN 'tribunal'::public.matter_status
    WHEN p_current_forum='high_court' THEN 'high_court'::public.matter_status
    WHEN p_current_forum='supreme_court' THEN 'supreme_court'::public.matter_status
    ELSE 'active'::public.matter_status
  END
$$;

CREATE OR REPLACE FUNCTION public.sync_matter_status_compatibility()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='UPDATE'
     AND NEW.work_state IS NOT DISTINCT FROM OLD.work_state
     AND NEW.current_forum IS NOT DISTINCT FROM OLD.current_forum
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.work_state:=public.matter_work_state_from_legacy(NEW.status);
    NEW.current_forum:=public.matter_current_forum_from_legacy(NEW.status);
  ELSIF TG_OP='INSERT' AND NEW.status IS DISTINCT FROM 'active'::public.matter_status
     AND NEW.work_state='active' AND NEW.current_forum='adjudication' THEN
    NEW.work_state:=public.matter_work_state_from_legacy(NEW.status);
    NEW.current_forum:=public.matter_current_forum_from_legacy(NEW.status);
  ELSE
    NEW.status:=public.matter_legacy_status(NEW.work_state,NEW.current_forum);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER matters_sync_status_compatibility
BEFORE INSERT OR UPDATE OF status,work_state,current_forum ON public.matters
FOR EACH ROW EXECUTE FUNCTION public.sync_matter_status_compatibility();

-- Canonical Activity definitions. Each changed dimension receives one stable
-- event/outbox pair; command receipt replay returns before these appends.
INSERT INTO public.activity_event_definitions(
  event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key
) VALUES
  ('matter.profile_updated',1,'record',ARRAY['matter'],'matter','{"changed_fields":"code"}','matter.profile_updated'),
  ('matter.work_state_changed',1,'lifecycle',ARRAY['matter'],'matter','{"from":"code","to":"code"}','matter.work_state_changed'),
  ('matter.forum_changed',1,'record',ARRAY['matter'],'matter','{"from":"code","to":"code"}','matter.forum_changed'),
  ('matter.closed',1,'lifecycle',ARRAY['matter'],'matter','{}','matter.closed'),
  ('matter.reopened',1,'lifecycle',ARRAY['matter'],'matter','{}','matter.reopened')
ON CONFLICT (event_type,event_version) DO NOTHING;

-- The typed overloads are the live write path. Legacy overloads remain below
-- as compatibility entry points, but delegate to this same governed path.
CREATE OR REPLACE FUNCTION public.create_matter_command(
  p_client_id uuid,p_title text,p_financial_year text,p_description text,
  p_work_state public.matter_work_state,p_current_forum public.matter_current_forum,p_idempotency_key uuid
) RETURNS TABLE(code text,matter_id uuid,client_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_current_count integer:=0; v_active_count integer:=0;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.matter_command_receipts%ROWTYPE;
  v_title text:=NULLIF(btrim(p_title),''); v_financial_year text:=NULLIF(btrim(p_financial_year),'');
  v_description text:=NULLIF(btrim(p_description),''); v_fingerprint text; v_legacy_fingerprint text; v_matter public.matters%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_client_id IS NULL OR p_idempotency_key IS NULL OR v_title IS NULL
     OR length(v_title) NOT BETWEEN 2 AND 300 OR v_financial_year IS NULL OR length(v_financial_year)>40
     OR length(coalesce(v_description,''))>10000 OR p_work_state IS NULL OR p_current_forum IS NULL THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,141));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP v_current_count:=v_current_count+1; IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF; END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  IF p_work_state='closed' AND v_membership.role<>'admin'
     AND NOT EXISTS(SELECT 1 FROM public.organisations o WHERE o.id=v_membership.org_id AND o.owner_membership_id=v_membership.id) THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','create.v2','client_id',p_client_id,'title',v_title,'financial_year',v_financial_year,
    'description',v_description,'work_state',p_work_state,'current_forum',p_current_forum
  )::text,'utf8'),'sha256'),'hex');
  v_legacy_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','create','client_id',p_client_id,'title',v_title,'financial_year',v_financial_year,
    'description',v_description,'status',public.matter_legacy_status(p_work_state,p_current_forum)
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.matter_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'create'
       OR v_receipt.request_fingerprint<>ALL(ARRAY[v_fingerprint,v_legacy_fingerprint]) THEN
      RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.matters m WHERE m.id=v_receipt.matter_id AND m.org_id=v_membership.org_id AND m.record_state='active' AND m.deleted_at IS NULL) THEN
      RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok',v_receipt.matter_id,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;
  PERFORM 1 FROM public.clients c WHERE c.id=p_client_id AND c.org_id=v_membership.org_id AND c.record_state='active' AND c.deleted_at IS NULL FOR KEY SHARE;
  IF NOT FOUND THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  BEGIN
    INSERT INTO public.matters(org_id,client_id,title,financial_year,description,work_state,current_forum)
    VALUES(v_membership.org_id,p_client_id,v_title,v_financial_year,v_description,p_work_state,p_current_forum)
    RETURNING * INTO v_matter;
  EXCEPTION WHEN unique_violation THEN RETURN QUERY SELECT 'identifier_conflict',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'matter_created','matter',v_matter.id,format('Created matter "%s"',v_title));
  PERFORM public.append_activity_event(v_membership.org_id,'matter.profile_updated',1::smallint,'user',v_actor,'Member','matter',v_matter.id,v_matter.client_id,v_matter.id,v_matter.title,'Matter created',jsonb_build_object('changed_fields','created'),'matter',v_matter.id,NULL,p_idempotency_key,NULL,'matter.create.'||p_idempotency_key::text,now());
  INSERT INTO public.matter_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,matter_id,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'create',v_fingerprint,v_matter.id,v_matter.client_id,v_matter.revision);
  RETURN QUERY SELECT 'ok',v_matter.id,v_matter.client_id,v_matter.revision,false;
END $$;

CREATE OR REPLACE FUNCTION public.update_matter_command(
  p_matter_id uuid,p_expected_revision bigint,p_title text,p_description text,
  p_work_state public.matter_work_state,p_current_forum public.matter_current_forum,p_idempotency_key uuid
) RETURNS TABLE(code text,matter_id uuid,client_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid(); v_current_count integer:=0; v_active_count integer:=0; v_is_privileged boolean:=false;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.matter_command_receipts%ROWTYPE;
  v_title text:=NULLIF(btrim(p_title),''); v_description text:=NULLIF(btrim(p_description),'');
  v_fingerprint text; v_legacy_fingerprint text; v_client_id uuid;
  v_matter public.matters%ROWTYPE; v_previous public.matters%ROWTYPE; v_changed_fields text:='';
BEGIN
  IF v_actor IS NULL OR p_matter_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_idempotency_key IS NULL
     OR v_title IS NULL OR length(v_title) NOT BETWEEN 2 AND 300 OR length(coalesce(v_description,''))>10000
     OR p_work_state IS NULL OR p_current_forum IS NULL THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,141));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP v_current_count:=v_current_count+1; IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF; END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  v_is_privileged:=v_membership.role='admin' OR EXISTS(SELECT 1 FROM public.organisations o WHERE o.id=v_membership.org_id AND o.owner_membership_id=v_membership.id);
  IF p_work_state='closed' AND NOT v_is_privileged THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','update.v2','matter_id',p_matter_id,'expected_revision',p_expected_revision,'title',v_title,
    'description',v_description,'work_state',p_work_state,'current_forum',p_current_forum
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.matter_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    SELECT encode(extensions.digest(convert_to(jsonb_build_object(
      'command','update','matter_id',p_matter_id,'expected_revision',p_expected_revision,'title',v_title,
      'financial_year',m.financial_year,'description',v_description,'status',public.matter_legacy_status(p_work_state,p_current_forum)
    )::text,'utf8'),'sha256'),'hex') INTO v_legacy_fingerprint
    FROM public.matters m WHERE m.id=v_receipt.matter_id AND m.org_id=v_membership.org_id;
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'update'
       OR (v_receipt.request_fingerprint IS DISTINCT FROM v_fingerprint
           AND v_receipt.request_fingerprint IS DISTINCT FROM v_legacy_fingerprint) THEN
      RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(
      SELECT 1 FROM public.matters m
      JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
      WHERE m.id=v_receipt.matter_id AND m.client_id=v_receipt.client_id
        AND m.org_id=v_membership.org_id AND m.record_state='active' AND m.deleted_at IS NULL
        AND c.record_state='active' AND c.deleted_at IS NULL
    ) THEN
      RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok',v_receipt.matter_id,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;
  SELECT m.client_id INTO v_client_id FROM public.matters m
  WHERE m.id=p_matter_id AND m.org_id=v_membership.org_id
    AND m.record_state='active' AND m.deleted_at IS NULL;
  IF v_client_id IS NULL THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  PERFORM 1 FROM public.clients c
  WHERE c.id=v_client_id AND c.org_id=v_membership.org_id
    AND c.record_state='active' AND c.deleted_at IS NULL
  FOR SHARE;
  IF NOT FOUND THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO v_matter FROM public.matters m WHERE m.id=p_matter_id AND m.client_id=v_client_id
    AND m.org_id=v_membership.org_id AND m.record_state='active' AND m.deleted_at IS NULL FOR UPDATE;
  IF v_matter.id IS NULL THEN RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF v_matter.revision<>p_expected_revision THEN RETURN QUERY SELECT 'conflict',v_matter.id,v_matter.client_id,v_matter.revision,false; RETURN; END IF;
  IF (v_matter.work_state='closed' OR p_work_state='closed') AND NOT v_is_privileged THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  v_previous:=v_matter;
  UPDATE public.matters AS m SET title=v_title,description=v_description,work_state=p_work_state,
    current_forum=p_current_forum,revision=m.revision+1 WHERE m.id=v_matter.id RETURNING * INTO v_matter;
  IF v_previous.title IS DISTINCT FROM v_matter.title OR v_previous.description IS DISTINCT FROM v_matter.description THEN
    v_changed_fields:=concat_ws('_',CASE WHEN v_previous.title IS DISTINCT FROM v_matter.title THEN 'title' END,CASE WHEN v_previous.description IS DISTINCT FROM v_matter.description THEN 'synopsis' END);
    PERFORM public.append_activity_event(v_membership.org_id,'matter.profile_updated',1::smallint,'user',v_actor,'Member','matter',v_matter.id,v_matter.client_id,v_matter.id,v_matter.title,'Matter profile updated',jsonb_build_object('changed_fields',v_changed_fields),'matter',v_matter.id,NULL,p_idempotency_key,NULL,'matter.profile.'||p_idempotency_key::text,now());
  END IF;
  IF v_previous.work_state IS DISTINCT FROM v_matter.work_state THEN
    PERFORM public.append_activity_event(v_membership.org_id,CASE WHEN v_matter.work_state='closed' THEN 'matter.closed' WHEN v_previous.work_state='closed' THEN 'matter.reopened' ELSE 'matter.work_state_changed' END,1::smallint,'user',v_actor,'Member','matter',v_matter.id,v_matter.client_id,v_matter.id,v_matter.title,CASE WHEN v_matter.work_state='closed' THEN 'Matter closed' WHEN v_previous.work_state='closed' THEN 'Matter reopened' ELSE 'Matter work state changed' END,CASE WHEN v_matter.work_state='closed' OR v_previous.work_state='closed' THEN '{}'::jsonb ELSE jsonb_build_object('from',v_previous.work_state,'to',v_matter.work_state) END,'matter',v_matter.id,NULL,p_idempotency_key,NULL,'matter.state.'||p_idempotency_key::text,now());
  END IF;
  IF v_previous.current_forum IS DISTINCT FROM v_matter.current_forum THEN
    PERFORM public.append_activity_event(v_membership.org_id,'matter.forum_changed',1::smallint,'user',v_actor,'Member','matter',v_matter.id,v_matter.client_id,v_matter.id,v_matter.title,'Matter forum changed',jsonb_build_object('from',v_previous.current_forum,'to',v_matter.current_forum),'matter',v_matter.id,NULL,p_idempotency_key,NULL,'matter.forum.'||p_idempotency_key::text,now());
  END IF;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'matter_updated','matter',v_matter.id,format('Updated matter "%s"',v_title));
  INSERT INTO public.matter_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,matter_id,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'update',v_fingerprint,v_matter.id,v_matter.client_id,v_matter.revision);
  RETURN QUERY SELECT 'ok',v_matter.id,v_matter.client_id,v_matter.revision,false;
END $$;

-- Governed compatibility overloads for legacy callers. Financial year is
-- retained but not changed here; that separate identity/placement workflow is
-- outside this normalization step.
CREATE OR REPLACE FUNCTION public.create_matter_command(
  p_client_id uuid,p_title text,p_financial_year text,p_description text,p_status public.matter_status,p_idempotency_key uuid
) RETURNS TABLE(code text,matter_id uuid,client_id uuid,revision bigint,replayed boolean)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT * FROM public.create_matter_command(p_client_id,p_title,p_financial_year,p_description,
    public.matter_work_state_from_legacy(coalesce(p_status,'active')),
    public.matter_current_forum_from_legacy(coalesce(p_status,'active')),p_idempotency_key)
$$;

CREATE OR REPLACE FUNCTION public.update_matter_command(
  p_matter_id uuid,p_expected_revision bigint,p_title text,p_financial_year text,p_description text,p_status public.matter_status,p_idempotency_key uuid
) RETURNS TABLE(code text,matter_id uuid,client_id uuid,revision bigint,replayed boolean)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT * FROM public.update_matter_command(p_matter_id,p_expected_revision,p_title,p_description,
    public.matter_work_state_from_legacy(p_status),public.matter_current_forum_from_legacy(p_status),p_idempotency_key)
$$;

REVOKE ALL ON FUNCTION public.create_matter_command(uuid,text,text,text,public.matter_work_state,public.matter_current_forum,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.update_matter_command(uuid,bigint,text,text,public.matter_work_state,public.matter_current_forum,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_matter_command(uuid,text,text,text,public.matter_work_state,public.matter_current_forum,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_matter_command(uuid,bigint,text,text,public.matter_work_state,public.matter_current_forum,uuid) TO authenticated;

-- Enrich the exact active/Trash route projection without weakening the proven
-- tenant, lineage, lifecycle, retention, and membership implementation.
ALTER FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid)
  RENAME TO get_exact_trashed_resource_projection_v00140;
REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection_v00140(public.trash_resource_type,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_exact_trashed_resource_projection(
  p_resource_type public.trash_resource_type,p_resource_id uuid,p_expected_matter_id uuid DEFAULT NULL
) RETURNS TABLE(
  resource_id uuid,resource_type public.trash_resource_type,membership_id uuid,cause public.resource_trash_cause,
  parent_membership_id uuid,operation_id uuid,root_resource_id uuid,root_resource_type public.trash_resource_type,
  root_resource_name text,operation_state public.trash_operation_state,trashed_at timestamptz,trashed_by uuid,
  trashed_by_name text,retention_mode public.trash_retention_mode,retention_days integer,purge_eligible_at timestamptz,
  auto_purge_enabled boolean,auto_purge_at timestamptz,purge_scheduled_at timestamptz,blocker_count integer,
  can_restore boolean,resource_record jsonb,related_matters jsonb,related_documents jsonb,related_links jsonb,
  related_wiki_sections jsonb,related_notes jsonb,related_inspector_metadata jsonb
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT base.resource_id,base.resource_type,base.membership_id,base.cause,base.parent_membership_id,base.operation_id,
    base.root_resource_id,base.root_resource_type,base.root_resource_name,base.operation_state,base.trashed_at,base.trashed_by,
    base.trashed_by_name,base.retention_mode,base.retention_days,base.purge_eligible_at,base.auto_purge_enabled,base.auto_purge_at,
    base.purge_scheduled_at,base.blocker_count,base.can_restore,
    CASE WHEN base.resource_type='matter' AND selected_matter.id IS NOT NULL THEN base.resource_record || jsonb_build_object(
      'work_state',selected_matter.work_state,'current_forum',selected_matter.current_forum,'revision',selected_matter.revision
    ) ELSE base.resource_record END,
    coalesce(enriched_matters.value,base.related_matters),base.related_documents,base.related_links,
    base.related_wiki_sections,base.related_notes,base.related_inspector_metadata
  FROM public.get_exact_trashed_resource_projection_v00140(p_resource_type,p_resource_id,p_expected_matter_id) base
  LEFT JOIN public.matters selected_matter ON base.resource_type='matter' AND selected_matter.id=base.resource_id
  LEFT JOIN LATERAL (
    SELECT coalesce(jsonb_agg(item.value || jsonb_build_object(
      'work_state',m.work_state,'current_forum',m.current_forum,'revision',m.revision
    ) ORDER BY item.ordinality),'[]'::jsonb) value
    FROM jsonb_array_elements(base.related_matters) WITH ORDINALITY item(value,ordinality)
    JOIN public.matters m ON m.id=(item.value->>'id')::uuid
  ) enriched_matters ON true
$$;
REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid) TO authenticated;

-- Cut all currently installed server gates that identify a Matter's writable
-- lifecycle through the overloaded legacy status over to typed work_state.
DO $rewrite_live_matter_gates$
DECLARE routine record; definition text; rewritten text;
BEGIN
  FOR routine IN
    SELECT procedure.oid
    FROM pg_catalog.pg_proc AS procedure
    JOIN pg_catalog.pg_namespace AS namespace ON namespace.oid=procedure.pronamespace
    WHERE namespace.nspname='public' AND procedure.prokind='f'
      AND procedure.proname NOT IN ('matter_work_state_from_legacy','matter_current_forum_from_legacy','matter_legacy_status','sync_matter_status_compatibility')
      AND procedure.prosrc ~ E'(m|matter|matter_row|assigned_matter)\\.status[[:space:]]*(=|<>)[[:space:]]*''active'''
  LOOP
    definition:=pg_catalog.pg_get_functiondef(routine.oid);
    rewritten:=pg_catalog.regexp_replace(definition,
      E'(m|matter|matter_row|assigned_matter)\\.status[[:space:]]*(=|<>)[[:space:]]*''active''(::public\\.matter_status)?',
      E'\\1.work_state \\2 ''active''::public.matter_work_state','g');
    IF rewritten=definition THEN RAISE EXCEPTION 'Failed to rewrite live Matter lifecycle gate %',routine.oid; END IF;
    EXECUTE rewritten;
  END LOOP;
END $rewrite_live_matter_gates$;

REVOKE ALL ON FUNCTION public.matter_work_state_from_legacy(public.matter_status),
  public.matter_current_forum_from_legacy(public.matter_status),
  public.matter_legacy_status(public.matter_work_state,public.matter_current_forum),
  public.sync_matter_status_compatibility() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
