-- Normal verified-email create-or-join onboarding. Organisation creation and
-- invitation acceptance share the existing per-user serialization boundary.
BEGIN;

CREATE TABLE public.organisation_creation_command_receipts (
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  requested_name text NOT NULL,
  result_code text NOT NULL,
  result_org_id uuid REFERENCES public.organisations(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_user_id,idempotency_key),
  CONSTRAINT organisation_creation_receipt_name_length
    CHECK(char_length(requested_name) BETWEEN 2 AND 200),
  CONSTRAINT organisation_creation_receipt_result_shape
    CHECK((result_code='ok' AND result_org_id IS NOT NULL)
      OR (result_code<>'ok' AND result_org_id IS NULL))
);

ALTER TABLE public.organisation_creation_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_creation_command_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.organisation_creation_command_receipts
  FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO public.activity_event_definitions(
  event_type,event_version,category,subject_types,default_visibility,
  metadata_contract,renderer_key
) VALUES(
  'organisation.created',1,'security',ARRAY['organisation'],'organisation',
  '{}'::jsonb,'organisation.created'
);

CREATE OR REPLACE FUNCTION public.create_organisation(
  p_name text,p_idempotency_key uuid DEFAULT NULL
)
RETURNS TABLE(code text,org_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_name text:=nullif(btrim(p_name),'');
  v_org uuid;
  v_owner_membership uuid;
  v_receipt public.organisation_creation_command_receipts%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR v_name IS NULL
     OR char_length(v_name) NOT BETWEEN 2 AND 200 OR v_name ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid;
    RETURN;
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM auth.users auth_user
    WHERE auth_user.id=v_actor AND auth_user.email_confirmed_at IS NOT NULL
  ) THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text,801)
  );
  SELECT * INTO v_receipt
  FROM public.organisation_creation_command_receipts receipt
  WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.actor_user_id IS NOT NULL THEN
    IF v_receipt.requested_name IS DISTINCT FROM v_name THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code,v_receipt.result_org_id;
    END IF;
    RETURN;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.administration_events event
    WHERE event.actor_user_id=v_actor AND event.idempotency_key=p_idempotency_key
  ) OR EXISTS(
    SELECT 1 FROM public.organisation_invitation_command_receipts receipt
    WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key
  ) THEN
    RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid;
    RETURN;
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.organisation_memberships membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended')
    FOR KEY SHARE
  ) THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid;
    RETURN;
  END IF;

  INSERT INTO public.organisations(name,created_by)
  VALUES(v_name,v_actor)
  RETURNING id INTO v_org;

  SELECT membership.id INTO v_owner_membership
  FROM public.organisation_memberships membership
  JOIN public.organisations organisation
    ON organisation.id=membership.org_id
   AND organisation.owner_membership_id=membership.id
  WHERE membership.org_id=v_org AND membership.user_id=v_actor
    AND membership.role='admin' AND membership.state='active';
  IF v_owner_membership IS NULL THEN
    RAISE EXCEPTION 'organisation creation did not establish owner membership'
      USING ERRCODE='integrity_constraint_violation';
  END IF;

  INSERT INTO public.organisation_storage_policies(org_id)
  VALUES(v_org) ON CONFLICT ON CONSTRAINT organisation_storage_policies_pkey
  DO NOTHING;
  IF NOT EXISTS(
       SELECT 1 FROM public.organisation_operational_settings settings
       WHERE settings.org_id=v_org
     ) OR NOT EXISTS(
       SELECT 1 FROM public.organisation_retention_settings retention
       WHERE retention.org_id=v_org
     ) OR NOT EXISTS(
       SELECT 1 FROM public.organisation_storage_policies storage_policy
       WHERE storage_policy.org_id=v_org
     ) THEN
    RAISE EXCEPTION 'organisation default policy initialization failed'
      USING ERRCODE='integrity_constraint_violation';
  END IF;

  INSERT INTO public.organisation_creation_command_receipts(
    actor_user_id,idempotency_key,requested_name,result_code,result_org_id
  ) VALUES(v_actor,p_idempotency_key,v_name,'ok',v_org);
  INSERT INTO public.administration_events(
    org_id,event_kind,actor_user_id,target_user_id,correlation_id,idempotency_key
  ) VALUES(
    v_org,'organisation_creation.completed.v1',v_actor,v_actor,
    p_idempotency_key,p_idempotency_key
  );
  INSERT INTO public.activity_logs(
    org_id,user_id,action,entity_type,entity_id,description,metadata
  ) VALUES(
    v_org,v_actor,'organisation.created','organisation',v_org,
    'Created organisation workspace','{}'::jsonb
  );
  PERFORM public.append_activity_event(
    v_org,'organisation.created',1::smallint,'user'::public.activity_actor_kind,v_actor,'Member',
    'organisation',v_org,NULL,NULL,'Organisation workspace',
    'Created organisation workspace','{}'::jsonb,
    'organisation',v_org,NULL,p_idempotency_key,NULL,
    'organisation.create.'||v_actor::text||'.'||p_idempotency_key::text,
    clock_timestamp()
  );
  RETURN QUERY SELECT 'ok'::text,v_org;
END $$;

CREATE OR REPLACE FUNCTION public.get_my_pending_organisation_invites()
RETURNS TABLE(id uuid,role public.org_member_role,org_name text,revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT invite.id,invite.role,organisation.name,invite.revision
  FROM public.organisation_invites invite
  JOIN public.organisations organisation ON organisation.id=invite.org_id
  JOIN auth.users auth_user ON auth_user.id=auth.uid()
  WHERE invite.state='pending' AND invite.expires_at>clock_timestamp()
    AND auth_user.email_confirmed_at IS NOT NULL
    AND invite.normalized_email=lower(auth_user.email)
    AND NOT EXISTS(
      SELECT 1 FROM public.organisation_memberships membership
      WHERE membership.user_id=auth.uid()
        AND membership.state IN ('active','suspended')
    )
  ORDER BY invite.created_at,invite.id
$$;

REVOKE ALL ON FUNCTION
  public.create_organisation(text,uuid),
  public.get_my_pending_organisation_invites()
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION
  public.create_organisation(text,uuid),
  public.get_my_pending_organisation_invites()
  TO authenticated;

COMMENT ON FUNCTION public.create_organisation(text,uuid) IS
  'Verified-email, serialized and idempotent organisation creation with initial Owner/Admin membership, required defaults and durable events.';
COMMENT ON FUNCTION public.get_my_pending_organisation_invites() IS
  'Verified-account pending invitations across organisations, available only while the caller has no active or suspended membership.';

COMMIT;
