-- Capability-checked, replay-safe matter create/update commands.

ALTER TABLE public.matters
  ADD COLUMN revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1);

CREATE TABLE public.matter_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('create', 'update')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  matter_id uuid NOT NULL,
  client_id uuid NOT NULL,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX matter_command_receipts_actor_org_created_idx
  ON public.matter_command_receipts (actor_user_id, org_id, created_at DESC);

ALTER TABLE public.matter_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_command_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.matter_command_receipts FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY IF EXISTS "matters_insert" ON public.matters;
DROP POLICY IF EXISTS "matters_update" ON public.matters;
REVOKE INSERT, UPDATE ON TABLE public.matters FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_matter_command(
  p_client_id uuid,
  p_title text,
  p_financial_year text,
  p_description text,
  p_status public.matter_status,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, matter_id uuid, client_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid(); v_current_count integer := 0; v_active_count integer := 0;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.matter_command_receipts%ROWTYPE;
  v_title text := NULLIF(btrim(p_title), ''); v_financial_year text := NULLIF(btrim(p_financial_year), '');
  v_description text := NULLIF(btrim(p_description), ''); v_status public.matter_status := COALESCE(p_status, 'active'::public.matter_status);
  v_fingerprint text; v_matter public.matters%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_client_id IS NULL OR p_idempotency_key IS NULL OR v_title IS NULL
     OR length(v_title) NOT BETWEEN 2 AND 300 OR v_financial_year IS NULL OR length(v_financial_year)>40
     OR length(COALESCE(v_description,''))>10000 THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,127));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','create','client_id',p_client_id,'title',v_title,'financial_year',v_financial_year,
    'description',v_description,'status',v_status
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.matter_command_receipts AS receipt WHERE receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'create' OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.matters AS matter WHERE matter.id=v_receipt.matter_id AND matter.org_id=v_membership.org_id AND matter.record_state='active' AND matter.deleted_at IS NULL) THEN
      RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.matter_id,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;

  PERFORM 1 FROM public.clients AS client WHERE client.id=p_client_id AND client.org_id=v_membership.org_id
    AND client.record_state='active' AND client.deleted_at IS NULL FOR KEY SHARE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  BEGIN
    INSERT INTO public.matters(org_id,client_id,title,financial_year,description,status)
    VALUES(v_membership.org_id,p_client_id,v_title,v_financial_year,v_description,v_status)
    RETURNING * INTO v_matter;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'identifier_conflict'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'matter_created','matter',v_matter.id,format('Created matter "%s"',v_title));
  INSERT INTO public.matter_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,matter_id,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'create',v_fingerprint,v_matter.id,v_matter.client_id,v_matter.revision);
  RETURN QUERY SELECT 'ok'::text,v_matter.id,v_matter.client_id,v_matter.revision,false;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_matter_command(
  p_matter_id uuid,
  p_expected_revision bigint,
  p_title text,
  p_financial_year text,
  p_description text,
  p_status public.matter_status,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, matter_id uuid, client_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid(); v_current_count integer := 0; v_active_count integer := 0;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.matter_command_receipts%ROWTYPE;
  v_title text := NULLIF(btrim(p_title), ''); v_financial_year text := NULLIF(btrim(p_financial_year), '');
  v_description text := NULLIF(btrim(p_description), ''); v_fingerprint text; v_matter public.matters%ROWTYPE;
  v_previous_financial_year text;
BEGIN
  IF v_actor IS NULL OR p_matter_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
     OR p_idempotency_key IS NULL OR v_title IS NULL OR length(v_title) NOT BETWEEN 2 AND 300
     OR v_financial_year IS NULL OR length(v_financial_year)>40 OR p_status IS NULL
     OR length(COALESCE(v_description,''))>10000 THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,127));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','update','matter_id',p_matter_id,'expected_revision',p_expected_revision,'title',v_title,
    'financial_year',v_financial_year,'description',v_description,'status',p_status
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.matter_command_receipts AS receipt WHERE receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'update' OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.matters AS matter WHERE matter.id=v_receipt.matter_id AND matter.org_id=v_membership.org_id AND matter.record_state='active' AND matter.deleted_at IS NULL) THEN
      RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.matter_id,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;

  SELECT * INTO v_matter FROM public.matters AS matter
  WHERE matter.id=p_matter_id AND matter.org_id=v_membership.org_id
    AND matter.record_state='active' AND matter.deleted_at IS NULL FOR UPDATE;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  IF v_matter.revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'conflict'::text,v_matter.id,v_matter.client_id,v_matter.revision,false; RETURN;
  END IF;

  v_previous_financial_year:=v_matter.financial_year;
  UPDATE public.matters AS matter SET title=v_title,financial_year=v_financial_year,
    description=v_description,status=p_status,revision=matter.revision+1
  WHERE matter.id=v_matter.id RETURNING * INTO v_matter;
  IF v_financial_year<>'Unknown FY' AND v_financial_year IS DISTINCT FROM v_previous_financial_year THEN
    UPDATE public.documents AS document SET financial_year=v_financial_year
    WHERE document.matter_id=v_matter.id AND document.org_id=v_membership.org_id
      AND document.record_state='active' AND document.deleted_at IS NULL
      AND (document.financial_year='Unknown FY' OR document.financial_year IS NULL);
  END IF;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'matter_updated','matter',v_matter.id,format('Updated matter "%s"',v_title));
  INSERT INTO public.matter_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,matter_id,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'update',v_fingerprint,v_matter.id,v_matter.client_id,v_matter.revision);
  RETURN QUERY SELECT 'ok'::text,v_matter.id,v_matter.client_id,v_matter.revision,false;
END;
$$;

REVOKE ALL ON FUNCTION public.create_matter_command(uuid,text,text,text,public.matter_status,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.update_matter_command(uuid,bigint,text,text,text,public.matter_status,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_matter_command(uuid,text,text,text,public.matter_status,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_matter_command(uuid,bigint,text,text,text,public.matter_status,uuid) TO authenticated;
