-- Capability-checked, replay-safe client create/update commands.

ALTER TABLE public.clients
  ADD COLUMN revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1);

CREATE TABLE public.client_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('create', 'update')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  client_id uuid NOT NULL,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX client_command_receipts_actor_org_created_idx
  ON public.client_command_receipts (actor_user_id, org_id, created_at DESC);

ALTER TABLE public.client_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.client_command_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.client_command_receipts FROM PUBLIC, anon, authenticated, service_role;

DROP POLICY IF EXISTS "clients_insert" ON public.clients;
DROP POLICY IF EXISTS "clients_update" ON public.clients;
REVOKE INSERT, UPDATE ON TABLE public.clients FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_client_command(
  p_name text, p_gstin text, p_pan text, p_idempotency_key uuid
)
RETURNS TABLE(code text, client_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid(); v_current_count integer := 0; v_active_count integer := 0;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.client_command_receipts%ROWTYPE;
  v_name text := NULLIF(btrim(p_name), ''); v_gstin text := NULLIF(upper(btrim(p_gstin)), '');
  v_pan text := NULLIF(upper(btrim(p_pan)), ''); v_fingerprint text; v_client public.clients%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 200
     OR (v_gstin IS NOT NULL AND v_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
     OR (v_pan IS NOT NULL AND v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$') THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,125));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','create','name',v_name,'gstin',v_gstin,'pan',v_pan
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.client_command_receipts AS receipt WHERE receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'create' OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.clients AS client WHERE client.id=v_receipt.client_id AND client.org_id=v_membership.org_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;

  BEGIN
    INSERT INTO public.clients(org_id,name,gstin,pan) VALUES(v_membership.org_id,v_name,v_gstin,v_pan) RETURNING * INTO v_client;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'identifier_conflict'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'client_created','client',v_client.id,format('Created client "%s"',v_name));
  INSERT INTO public.client_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'create',v_fingerprint,v_client.id,v_client.revision);
  RETURN QUERY SELECT 'ok'::text,v_client.id,v_client.revision,false;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_client_command(
  p_client_id uuid, p_expected_revision bigint, p_name text, p_gstin text, p_pan text, p_idempotency_key uuid
)
RETURNS TABLE(code text, client_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid(); v_current_count integer := 0; v_active_count integer := 0;
  v_membership public.organisation_memberships%ROWTYPE; v_receipt public.client_command_receipts%ROWTYPE;
  v_name text := NULLIF(btrim(p_name), ''); v_gstin text := NULLIF(upper(btrim(p_gstin)), '');
  v_pan text := NULLIF(upper(btrim(p_pan)), ''); v_fingerprint text; v_client public.clients%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_client_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
     OR p_idempotency_key IS NULL OR v_name IS NULL OR length(v_name) NOT BETWEEN 2 AND 200
     OR (v_gstin IS NOT NULL AND v_gstin !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
     OR (v_pan IS NOT NULL AND v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$') THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,125));
  FOR v_membership IN SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR UPDATE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_membership.state='active' THEN v_active_count:=v_active_count+1; END IF;
  END LOOP;
  IF v_current_count<>1 OR v_active_count<>1 OR v_membership.role='viewer' THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;

  v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object(
    'command','update','client_id',p_client_id,'expected_revision',p_expected_revision,
    'name',v_name,'gstin',v_gstin,'pan',v_pan
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.client_command_receipts AS receipt WHERE receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id<>v_actor OR v_receipt.org_id<>v_membership.org_id OR v_receipt.command<>'update' OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text,NULL::uuid,NULL::bigint,false;
    ELSIF NOT EXISTS(SELECT 1 FROM public.clients AS client WHERE client.id=v_receipt.client_id AND client.org_id=v_membership.org_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::bigint,false;
    ELSE RETURN QUERY SELECT 'ok'::text,v_receipt.client_id,v_receipt.result_revision,true;
    END IF; RETURN;
  END IF;

  SELECT * INTO v_client FROM public.clients AS client
  WHERE client.id=p_client_id AND client.org_id=v_membership.org_id
    AND client.record_state='active' AND client.deleted_at IS NULL FOR UPDATE;
  IF v_client.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  IF v_client.revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'conflict'::text,v_client.id,v_client.revision,false; RETURN;
  END IF;

  BEGIN
    UPDATE public.clients AS client SET name=v_name,gstin=v_gstin,pan=v_pan,
      revision=client.revision+1,updated_at=now()
    WHERE client.id=v_client.id RETURNING * INTO v_client;
  EXCEPTION WHEN unique_violation THEN
    RETURN QUERY SELECT 'identifier_conflict'::text,NULL::uuid,NULL::bigint,false; RETURN;
  END;
  INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description)
  VALUES(v_membership.org_id,v_actor,'client_updated','client',v_client.id,format('Updated client "%s"',v_name));
  INSERT INTO public.client_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,client_id,result_revision)
  VALUES(v_membership.org_id,v_actor,p_idempotency_key,'update',v_fingerprint,v_client.id,v_client.revision);
  RETURN QUERY SELECT 'ok'::text,v_client.id,v_client.revision,false;
END;
$$;

REVOKE ALL ON FUNCTION public.create_client_command(text,text,text,uuid) FROM PUBLIC,anon,service_role;
REVOKE ALL ON FUNCTION public.update_client_command(uuid,bigint,text,text,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_client_command(text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_client_command(uuid,bigint,text,text,text,uuid) TO authenticated;
