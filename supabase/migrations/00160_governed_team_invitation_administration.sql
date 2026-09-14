-- Governed Team invitation administration. This closes the legacy caller gaps
-- without restoring table access or exposing invitation selectors.
BEGIN;

ALTER TABLE public.organisation_invitation_command_receipts
  ADD COLUMN IF NOT EXISTS request_fingerprint text;

UPDATE public.organisation_invitation_command_receipts AS receipt
SET request_fingerprint = pg_catalog.encode(extensions.digest(
  receipt.command_kind || ':' || coalesce(receipt.invite_id::text, '') || ':' ||
  coalesce(receipt.result_org_id::text, ''), 'sha256'), 'hex')
WHERE receipt.request_fingerprint IS NULL;

ALTER TABLE public.organisation_invitation_command_receipts
  ALTER COLUMN request_fingerprint SET NOT NULL;
ALTER TABLE public.organisation_invitation_command_receipts
  ALTER COLUMN request_fingerprint SET DEFAULT repeat('0',64);
ALTER TABLE public.organisation_invitation_command_receipts
  ADD CONSTRAINT organisation_invitation_receipt_fingerprint_shape
  CHECK (request_fingerprint ~ '^[0-9a-f]{64}$');

CREATE OR REPLACE FUNCTION public.create_organisation_invite(
  p_email text,
  p_role public.org_member_role,
  p_selector_hash text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  code text, invite_id uuid, token_version integer, org_name text,
  inviter_name text, retry_after timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership_id uuid;
  v_org uuid;
  v_role public.org_member_role;
  v_owner boolean := false;
  v_email text := lower(btrim(p_email));
  v_invite uuid;
  v_retry timestamptz;
  v_fingerprint text;
  v_existing public.organisation_invites%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR p_email IS NULL
     OR p_role IS NULL OR p_role NOT IN ('associate','viewer','admin')
     OR p_selector_hash IS NULL OR p_selector_hash !~ '^[0-9a-f]{64}$'
     OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR char_length(v_email) > 320 OR v_email ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    RETURN;
  END IF;

  SELECT actor.membership_id,actor.org_id,actor.role
    INTO v_membership_id,v_org,v_role
  FROM public.current_active_tenant_membership() AS actor;
  IF v_membership_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    RETURN;
  END IF;
  SELECT organisation.owner_membership_id=v_membership_id INTO v_owner
  FROM public.organisations AS organisation WHERE organisation.id=v_org;
  IF (p_role='admin' AND NOT coalesce(v_owner,false))
     OR (p_role<>'admin' AND NOT ('team.invite.standard'=ANY(
       public.organisation_member_capabilities(v_role,coalesce(v_owner,false),'active')
     ))) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    RETURN;
  END IF;

  v_fingerprint := pg_catalog.encode(extensions.digest(v_org::text||':'||v_email||':'||p_role::text,'sha256'),'hex');
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text||':'||p_idempotency_key::text,160));
  SELECT * INTO v_existing FROM public.organisation_invites AS invite
  WHERE invite.invited_by_user_id=v_actor AND invite.idempotency_key=p_idempotency_key;
  IF v_existing.id IS NOT NULL THEN
    IF pg_catalog.encode(extensions.digest(v_existing.org_id::text||':'||v_existing.normalized_email||':'||v_existing.role::text,'sha256'),'hex')<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'already_processed'::text,v_existing.id,v_existing.token_version,NULL::text,NULL::text,NULL::timestamptz;
    END IF;
    RETURN;
  END IF;

  -- Serialize duplicate and rate-limit decisions for this organisation/address.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text,161));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_org::text||':'||v_email,162));
  -- Existing active or suspended membership is deliberately non-disclosing:
  -- invitation administration does not reveal which organisation holds it.
  IF EXISTS(
    SELECT 1 FROM auth.users AS recipient
    JOIN public.organisation_memberships AS membership ON membership.user_id=recipient.id
    WHERE lower(recipient.email)=v_email
      AND membership.state IN ('active','suspended')
  ) THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    RETURN;
  END IF;
  IF EXISTS(SELECT 1 FROM public.organisation_invites AS invite
            WHERE invite.org_id=v_org AND invite.normalized_email=v_email AND invite.state='pending') THEN
    RETURN QUERY SELECT 'pending_exists'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    RETURN;
  END IF;
  SELECT min(delivery.created_at)+interval '24 hours' INTO v_retry
  FROM public.organisation_invite_deliveries AS delivery
  JOIN public.organisation_invites AS invite ON invite.id=delivery.invite_id
  WHERE invite.normalized_email=v_email AND delivery.created_at>clock_timestamp()-interval '24 hours'
  HAVING count(*)>=3;
  IF v_retry IS NULL THEN
    SELECT min(delivery.created_at)+interval '24 hours' INTO v_retry
    FROM public.organisation_invite_deliveries AS delivery
    JOIN public.organisation_invites AS invite ON invite.id=delivery.invite_id
    WHERE invite.org_id=v_org AND delivery.created_at>clock_timestamp()-interval '24 hours'
    HAVING count(*)>=50;
  END IF;
  IF v_retry IS NOT NULL THEN
    RETURN QUERY SELECT 'rate_limited'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,v_retry;
    RETURN;
  END IF;

  INSERT INTO public.organisation_invites(
    org_id,normalized_email,role,selector_hash,invited_by_membership_id,
    invited_by_user_id,idempotency_key
  ) VALUES(v_org,v_email,p_role,p_selector_hash,v_membership_id,v_actor,p_idempotency_key)
  RETURNING id INTO v_invite;
  INSERT INTO public.organisation_invite_deliveries(
    invite_id,token_version,created_by,idempotency_key
  ) VALUES(v_invite,1,v_actor,p_idempotency_key);
  INSERT INTO public.organisation_invitation_command_receipts(
    actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id,
    request_fingerprint
  ) VALUES(v_actor,p_idempotency_key,'create',v_invite,'created',v_org,v_fingerprint);
  PERFORM public.invitation_event(v_org,'organisation_invitation.created.v1',v_actor,NULL,NULL,
    (SELECT invite.correlation_id FROM public.organisation_invites AS invite WHERE invite.id=v_invite),p_idempotency_key);
  RETURN QUERY SELECT 'created'::text,v_invite,1,organisation.name,
    coalesce(profile.display_name,'A team member'),NULL::timestamptz
  FROM public.organisations AS organisation
  LEFT JOIN public.user_profiles AS profile ON profile.user_id=v_actor
  WHERE organisation.id=v_org;
END $$;

CREATE OR REPLACE FUNCTION public.resend_organisation_invite(
  p_invite_id uuid,p_expected_revision bigint,p_selector_hash text,p_idempotency_key uuid
)
RETURNS TABLE(
  code text,invite_id uuid,token_version integer,org_name text,
  inviter_name text,retry_after timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_actor_membership uuid;
  v_actor_org uuid;
  v_actor_role public.org_member_role;
  v_owner boolean:=false;
  v_old public.organisation_invites%ROWTYPE;
  v_receipt public.organisation_invitation_command_receipts%ROWTYPE;
  v_new uuid;
  v_retry timestamptz;
  v_fingerprint text:=pg_catalog.encode(extensions.digest('resend:'||coalesce(p_invite_id::text,'')||':'||coalesce(p_expected_revision::text,''),'sha256'),'hex');
BEGIN
  IF v_actor IS NULL OR p_invite_id IS NULL OR p_expected_revision IS NULL
     OR p_idempotency_key IS NULL OR p_selector_hash IS NULL
     OR p_selector_hash !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  SELECT actor.membership_id,actor.org_id,actor.role INTO v_actor_membership,v_actor_org,v_actor_role
  FROM public.current_active_tenant_membership() AS actor;
  IF v_actor_membership IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text||':'||p_idempotency_key::text,160));
  SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts AS receipt
  WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.actor_user_id IS NOT NULL THEN
    IF v_receipt.command_kind<>'resend' OR v_receipt.request_fingerprint<>v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'already_processed'::text,v_receipt.invite_id,NULL::integer,NULL::text,NULL::text,NULL::timestamptz;
    END IF;
    RETURN;
  END IF;
  SELECT * INTO v_old FROM public.organisation_invites AS invite WHERE invite.id=p_invite_id FOR UPDATE;
  IF v_old.id IS NULL OR v_old.org_id<>v_actor_org THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  SELECT organisation.owner_membership_id=v_actor_membership INTO v_owner
  FROM public.organisations AS organisation WHERE organisation.id=v_actor_org;
  IF (v_old.role='admin' AND NOT coalesce(v_owner,false)) OR
     (v_old.role<>'admin' AND NOT ('team.invite.standard'=ANY(public.organisation_member_capabilities(v_actor_role,coalesce(v_owner,false),'active')))) THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  IF v_old.state<>'pending' OR v_old.expires_at<=clock_timestamp() THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  IF v_old.revision<>p_expected_revision THEN
    RETURN QUERY SELECT 'conflict'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor_org::text,161));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor_org::text||':'||v_old.normalized_email,162));
  SELECT min(delivery.created_at)+interval '24 hours' INTO v_retry
  FROM public.organisation_invite_deliveries AS delivery
  JOIN public.organisation_invites AS invite ON invite.id=delivery.invite_id
  WHERE invite.normalized_email=v_old.normalized_email AND delivery.created_at>clock_timestamp()-interval '24 hours'
  HAVING count(*)>=3;
  IF v_retry IS NULL THEN
    SELECT min(delivery.created_at)+interval '24 hours' INTO v_retry
    FROM public.organisation_invite_deliveries AS delivery
    JOIN public.organisation_invites AS invite ON invite.id=delivery.invite_id
    WHERE invite.org_id=v_actor_org AND delivery.created_at>clock_timestamp()-interval '24 hours'
    HAVING count(*)>=50;
  END IF;
  IF v_retry IS NOT NULL THEN
    RETURN QUERY SELECT 'rate_limited'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,v_retry; RETURN;
  END IF;
  UPDATE public.organisation_invites AS invite SET state='superseded',selector_hash=NULL,
    superseded_at=clock_timestamp(),lifecycle_actor_id=v_actor,superseded_by_id=NULL
  WHERE invite.id=v_old.id;
  INSERT INTO public.organisation_invites(
    org_id,normalized_email,role,selector_hash,token_version,expires_at,
    invited_by_membership_id,invited_by_user_id,idempotency_key,correlation_id
  ) VALUES(v_old.org_id,v_old.normalized_email,v_old.role,p_selector_hash,v_old.token_version+1,
    clock_timestamp()+interval '7 days',v_old.invited_by_membership_id,v_actor,p_idempotency_key,v_old.correlation_id)
  RETURNING id INTO v_new;
  UPDATE public.organisation_invites AS invite SET superseded_by_id=v_new WHERE invite.id=v_old.id;
  INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by,idempotency_key)
  VALUES(v_new,v_old.token_version+1,v_actor,p_idempotency_key);
  INSERT INTO public.organisation_invitation_command_receipts(
    actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id,request_fingerprint
  ) VALUES(v_actor,p_idempotency_key,'resend',v_new,'created',v_actor_org,v_fingerprint);
  PERFORM public.invitation_event(v_actor_org,'organisation_invitation.resent.v1',v_actor,NULL,NULL,v_old.correlation_id,p_idempotency_key);
  RETURN QUERY SELECT 'created'::text,v_new,v_old.token_version+1,organisation.name,
    coalesce(profile.display_name,'A team member'),NULL::timestamptz
  FROM public.organisations AS organisation
  LEFT JOIN public.user_profiles AS profile ON profile.user_id=v_actor
  WHERE organisation.id=v_actor_org;
END $$;

CREATE OR REPLACE FUNCTION public.transition_organisation_invite(
  p_invite_id uuid,p_expected_revision bigint,p_idempotency_key uuid,
  p_action text,p_reason text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_actor_membership uuid;
  v_actor_org uuid;
  v_actor_role public.org_member_role;
  v_owner boolean:=false;
  v_invite public.organisation_invites%ROWTYPE;
  v_email text;
  v_receipt public.organisation_invitation_command_receipts%ROWTYPE;
  v_reason text:=nullif(btrim(p_reason),'');
  v_fingerprint text:=pg_catalog.encode(extensions.digest(coalesce(p_action,'')||':'||coalesce(p_invite_id::text,'')||':'||coalesce(p_expected_revision::text,'')||':'||coalesce(v_reason,''),'sha256'),'hex');
BEGIN
  IF v_actor IS NULL OR p_invite_id IS NULL OR p_expected_revision IS NULL OR
     p_idempotency_key IS NULL OR p_action NOT IN ('reject','revoke') OR
     (v_reason IS NOT NULL AND (char_length(v_reason)>500 OR v_reason~'[[:cntrl:]]')) THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text||':'||p_idempotency_key::text,160));
  SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts AS receipt
  WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.actor_user_id IS NOT NULL THEN
    RETURN QUERY SELECT CASE WHEN v_receipt.command_kind=p_action AND v_receipt.request_fingerprint=v_fingerprint THEN 'ok' ELSE 'idempotency_subject_mismatch' END;
    RETURN;
  END IF;
  SELECT * INTO v_invite FROM public.organisation_invites AS invite WHERE invite.id=p_invite_id FOR UPDATE;
  IF v_invite.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
  IF p_action='reject' THEN
    SELECT lower(auth_user.email) INTO v_email FROM auth.users AS auth_user
    WHERE auth_user.id=v_actor AND auth_user.email_confirmed_at IS NOT NULL;
    IF v_email IS NULL OR v_email<>v_invite.normalized_email THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
  ELSE
    SELECT actor.membership_id,actor.org_id,actor.role INTO v_actor_membership,v_actor_org,v_actor_role
    FROM public.current_active_tenant_membership() AS actor;
    IF v_actor_membership IS NULL OR v_actor_org<>v_invite.org_id THEN RETURN QUERY SELECT 'not_allowed'::text; RETURN; END IF;
    SELECT organisation.owner_membership_id=v_actor_membership INTO v_owner
    FROM public.organisations AS organisation WHERE organisation.id=v_actor_org;
    IF (v_invite.role='admin' AND NOT coalesce(v_owner,false)) OR
       (v_invite.role<>'admin' AND NOT ('team.invite.standard'=ANY(public.organisation_member_capabilities(v_actor_role,coalesce(v_owner,false),'active')))) THEN
      RETURN QUERY SELECT 'not_allowed'::text; RETURN;
    END IF;
  END IF;
  IF v_invite.state<>'pending' OR v_invite.expires_at<=clock_timestamp() THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
  IF v_invite.revision<>p_expected_revision THEN RETURN QUERY SELECT 'conflict'::text; RETURN; END IF;
  UPDATE public.organisation_invites AS invite SET
    state=CASE WHEN p_action='reject' THEN 'rejected'::public.organisation_invite_state ELSE 'revoked'::public.organisation_invite_state END,
    selector_hash=NULL,
    rejected_at=CASE WHEN p_action='reject' THEN clock_timestamp() ELSE NULL END,
    revoked_at=CASE WHEN p_action='revoke' THEN clock_timestamp() ELSE NULL END,
    lifecycle_actor_id=v_actor,lifecycle_reason=v_reason
  WHERE invite.id=v_invite.id;
  INSERT INTO public.organisation_invitation_command_receipts(
    actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id,request_fingerprint
  ) VALUES(v_actor,p_idempotency_key,p_action,v_invite.id,'ok',v_invite.org_id,v_fingerprint);
  PERFORM public.invitation_event(v_invite.org_id,'organisation_invitation.'||CASE WHEN p_action='reject' THEN 'rejected' ELSE 'revoked' END||'.v1',
    v_actor,NULL,v_reason,v_invite.correlation_id,p_idempotency_key);
  RETURN QUERY SELECT 'ok'::text;
END $$;

CREATE OR REPLACE FUNCTION public.accept_organisation_invite(
  p_invite_id uuid DEFAULT NULL,p_selector_hash text DEFAULT NULL,
  p_nonce_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT gen_random_uuid()
)
RETURNS TABLE(code text,org_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_invite public.organisation_invites%ROWTYPE;
  v_receipt public.organisation_invitation_command_receipts%ROWTYPE;
  v_email text;
  v_membership uuid;
  v_current_count integer:=0;
  v_active_count integer:=0;
  v_current_org uuid;
  v_current_state public.organisation_membership_state;
  v_fingerprint text;
BEGIN
  IF v_actor IS NULL OR p_idempotency_key IS NULL OR
     ((p_invite_id IS NOT NULL)::integer+(p_selector_hash IS NOT NULL)::integer+(p_nonce_hash IS NOT NULL)::integer)<>1 OR
     (p_selector_hash IS NOT NULL AND p_selector_hash!~'^[0-9a-f]{64}$') OR
     (p_nonce_hash IS NOT NULL AND p_nonce_hash!~'^[0-9a-f]{64}$') THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_actor::text,801));
  IF p_invite_id IS NOT NULL THEN
    v_fingerprint:=pg_catalog.encode(extensions.digest('accept:'||p_invite_id::text,'sha256'),'hex');
    SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts AS receipt
    WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key;
    IF v_receipt.actor_user_id IS NOT NULL THEN
      IF v_receipt.command_kind='accept' AND v_receipt.request_fingerprint=v_fingerprint THEN
        RETURN QUERY SELECT v_receipt.result_code,v_receipt.result_org_id;
      ELSE RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid;
      END IF;
      RETURN;
    END IF;
  END IF;
  SELECT lower(auth_user.email) INTO v_email FROM auth.users AS auth_user
  WHERE auth_user.id=v_actor AND auth_user.email_confirmed_at IS NOT NULL;
  IF v_email IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
  IF p_nonce_hash IS NOT NULL THEN
    SELECT intent.invite_id INTO p_invite_id FROM public.organisation_invitation_accept_intents AS intent
    WHERE intent.nonce_hash=p_nonce_hash AND intent.consumed_at IS NULL AND intent.expires_at>clock_timestamp() FOR UPDATE;
  END IF;
  IF p_selector_hash IS NOT NULL THEN
    SELECT * INTO v_invite FROM public.organisation_invites AS invite
    WHERE invite.selector_hash=p_selector_hash AND invite.state='pending' FOR UPDATE;
  ELSE
    SELECT * INTO v_invite FROM public.organisation_invites AS invite WHERE invite.id=p_invite_id FOR UPDATE;
  END IF;
  IF v_invite.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
  v_fingerprint:=pg_catalog.encode(extensions.digest('accept:'||v_invite.id::text,'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts AS receipt
  WHERE receipt.actor_user_id=v_actor AND receipt.idempotency_key=p_idempotency_key;
  IF v_receipt.actor_user_id IS NOT NULL THEN
    IF v_receipt.command_kind='accept' AND v_receipt.request_fingerprint=v_fingerprint THEN RETURN QUERY SELECT v_receipt.result_code,v_receipt.result_org_id;
    ELSE RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid; END IF;
    RETURN;
  END IF;
  FOR v_membership,v_current_org,v_current_state IN
    SELECT membership.id,membership.org_id,membership.state FROM public.organisation_memberships AS membership
    WHERE membership.user_id=v_actor AND membership.state IN ('active','suspended') FOR KEY SHARE
  LOOP
    v_current_count:=v_current_count+1;
    IF v_current_state='active' THEN v_active_count:=v_active_count+1; END IF;
  END LOOP;
  IF v_current_count>1 THEN
    RAISE LOG 'organisation membership invariant violation during invitation acceptance for actor %',v_actor;
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN;
  END IF;
  IF v_invite.state='accepted' AND v_invite.accepted_by_user_id=v_actor AND
     v_current_count=1 AND v_active_count=1 AND v_current_org=v_invite.org_id THEN
    RETURN QUERY SELECT 'accepted'::text,v_invite.org_id; RETURN;
  END IF;
  IF v_invite.state<>'pending' OR v_invite.expires_at<=clock_timestamp() OR
     v_email<>v_invite.normalized_email OR v_current_count<>0 THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN;
  END IF;
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(v_invite.org_id,v_actor,v_invite.role)
  ON CONFLICT ON CONSTRAINT org_members_pkey DO NOTHING;
  SELECT membership.id INTO v_membership FROM public.organisation_memberships AS membership
  WHERE membership.org_id=v_invite.org_id AND membership.user_id=v_actor AND membership.state='active';
  IF v_membership IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
  UPDATE public.organisation_invites AS invite SET state='accepted',selector_hash=NULL,accepted_at=clock_timestamp(),
    accepted_by_user_id=v_actor,accepted_membership_id=v_membership,lifecycle_actor_id=v_actor
  WHERE invite.id=v_invite.id;
  IF p_nonce_hash IS NOT NULL THEN UPDATE public.organisation_invitation_accept_intents AS intent SET consumed_at=clock_timestamp() WHERE intent.nonce_hash=p_nonce_hash; END IF;
  INSERT INTO public.organisation_invitation_command_receipts(
    actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id,request_fingerprint
  ) VALUES(v_actor,p_idempotency_key,'accept',v_invite.id,'accepted',v_invite.org_id,v_fingerprint);
  PERFORM public.invitation_event(v_invite.org_id,'organisation_invitation.accepted.v1',v_actor,v_actor,NULL,v_invite.correlation_id,p_idempotency_key);
  RETURN QUERY SELECT 'accepted'::text,v_invite.org_id;
END $$;

DROP FUNCTION IF EXISTS public.get_organisation_invites();
CREATE FUNCTION public.get_organisation_invites(p_state text DEFAULT 'pending')
RETURNS TABLE(
  id uuid,role public.org_member_role,state public.organisation_invite_state,
  created_at timestamptz,expires_at timestamptz,revision bigint,authorized_email text
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_membership uuid;
  v_org uuid;
  v_role public.org_member_role;
  v_owner boolean:=false;
BEGIN
  IF p_state NOT IN ('pending','accepted','rejected','expired','revoked','superseded','all') THEN RETURN; END IF;
  SELECT actor.membership_id,actor.org_id,actor.role INTO v_membership,v_org,v_role
  FROM public.current_active_tenant_membership() AS actor;
  IF v_membership IS NULL THEN RETURN; END IF;
  SELECT organisation.owner_membership_id=v_membership INTO v_owner
  FROM public.organisations AS organisation WHERE organisation.id=v_org;
  IF NOT ('team.invite.standard'=ANY(public.organisation_member_capabilities(v_role,coalesce(v_owner,false),'active'))) THEN RETURN; END IF;
  RETURN QUERY
  SELECT invite.id,invite.role,invite.state,invite.created_at,invite.expires_at,
    invite.revision,invite.normalized_email
  FROM public.organisation_invites AS invite
  WHERE invite.org_id=v_org
    AND (p_state='all' OR invite.state::text=p_state)
    AND (p_state<>'pending' OR invite.expires_at>clock_timestamp())
  ORDER BY invite.created_at DESC,invite.id DESC
  LIMIT 200;
END $$;

REVOKE ALL ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid),
  public.resend_organisation_invite(uuid,bigint,text,uuid),
  public.transition_organisation_invite(uuid,bigint,uuid,text,text),
  public.accept_organisation_invite(uuid,text,text,uuid),
  public.get_organisation_invites(text)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid),
  public.resend_organisation_invite(uuid,bigint,text,uuid),
  public.transition_organisation_invite(uuid,bigint,uuid,text,text),
  public.accept_organisation_invite(uuid,text,text,uuid),
  public.get_organisation_invites(text)
  TO authenticated;

-- Canonical invitation tables remain RPC-only, including for service role.
REVOKE ALL ON public.org_invites,public.organisation_invites,
  public.organisation_invite_deliveries,public.organisation_invitation_accept_intents,
  public.organisation_invitation_command_receipts,public.administration_events
  FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
