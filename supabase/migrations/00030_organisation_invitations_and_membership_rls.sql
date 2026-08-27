-- Canonical, hash-only organisation invitation lifecycle and active-membership
-- RLS cutover. This migration deliberately retains org_invites only as a
-- restricted compatibility archive; browser clients use the RPCs below.
BEGIN;

CREATE TYPE public.organisation_invite_state AS ENUM
  ('pending', 'accepted', 'rejected', 'expired', 'revoked', 'superseded');

CREATE TABLE public.organisation_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  normalized_email text NOT NULL CHECK (normalized_email = lower(btrim(normalized_email)) AND normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' AND char_length(normalized_email) <= 320),
  role public.org_member_role NOT NULL,
  state public.organisation_invite_state NOT NULL DEFAULT 'pending',
  selector_hash text CHECK (selector_hash IS NULL OR selector_hash ~ '^[0-9a-f]{64}$'),
  token_version integer NOT NULL DEFAULT 1 CHECK (token_version > 0),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  invited_by_membership_id uuid REFERENCES public.organisation_memberships(id) ON DELETE RESTRICT,
  invited_by_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_by_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_membership_id uuid REFERENCES public.organisation_memberships(id) ON DELETE RESTRICT,
  accepted_at timestamptz,
  rejected_at timestamptz,
  revoked_at timestamptz,
  expired_at timestamptz,
  superseded_at timestamptz,
  lifecycle_actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  lifecycle_reason text CHECK (lifecycle_reason IS NULL OR char_length(lifecycle_reason) <= 500),
  superseded_by_id uuid REFERENCES public.organisation_invites(id) ON DELETE RESTRICT,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  idempotency_key uuid NOT NULL DEFAULT gen_random_uuid(),
  correlation_id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organisation_invites_pending_shape CHECK (
    (state = 'pending' AND selector_hash IS NOT NULL AND accepted_at IS NULL AND rejected_at IS NULL AND revoked_at IS NULL AND expired_at IS NULL AND superseded_at IS NULL)
    OR (state <> 'pending' AND selector_hash IS NULL)
  ),
  CONSTRAINT organisation_invites_accepted_shape CHECK (state <> 'accepted' OR accepted_at IS NOT NULL),
  CONSTRAINT organisation_invites_terminal_timestamp CHECK (
    (state <> 'rejected' OR rejected_at IS NOT NULL) AND (state <> 'revoked' OR revoked_at IS NOT NULL)
    AND (state <> 'expired' OR expired_at IS NOT NULL) AND (state <> 'superseded' OR superseded_at IS NOT NULL)
  )
);
CREATE UNIQUE INDEX organisation_invites_pending_email_unique ON public.organisation_invites(org_id, normalized_email) WHERE state = 'pending';
CREATE UNIQUE INDEX organisation_invites_pending_selector_unique ON public.organisation_invites(selector_hash) WHERE state = 'pending';
CREATE UNIQUE INDEX organisation_invites_actor_idempotency_unique ON public.organisation_invites(invited_by_user_id, idempotency_key);

CREATE TABLE public.organisation_invite_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id uuid NOT NULL REFERENCES public.organisation_invites(id) ON DELETE RESTRICT,
  token_version integer NOT NULL CHECK (token_version > 0),
  state text NOT NULL DEFAULT 'scheduled' CHECK (state IN ('scheduled', 'sent', 'failed')),
  provider_reference text CHECK (provider_reference IS NULL AND char_length(provider_reference) <= 200 OR provider_reference ~ '^[A-Za-z0-9._:-]{1,200}$'),
  error_code text CHECK (error_code IS NULL OR error_code ~ '^[a-z0-9_.-]{1,80}$'),
  created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL DEFAULT gen_random_uuid(),
  scheduled_at timestamptz NOT NULL DEFAULT now(), sent_at timestamptz, failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(invite_id, token_version), UNIQUE(created_by, idempotency_key),
  CHECK ((state = 'scheduled' AND sent_at IS NULL AND failed_at IS NULL)
      OR (state = 'sent' AND sent_at IS NOT NULL AND failed_at IS NULL)
      OR (state = 'failed' AND failed_at IS NOT NULL AND sent_at IS NULL))
);
CREATE INDEX organisation_invite_deliveries_created_idx ON public.organisation_invite_deliveries(created_at);

CREATE TABLE public.organisation_invitation_accept_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id uuid NOT NULL REFERENCES public.organisation_invites(id) ON DELETE RESTRICT,
  nonce_hash text NOT NULL UNIQUE CHECK (nonce_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz NOT NULL CHECK (expires_at > created_at AND expires_at <= created_at + interval '20 minutes'),
  consumed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.administration_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  event_kind text NOT NULL CHECK (event_kind ~ '^organisation_[a-z_]+\.[a-z_]+\.v[1-9][0-9]*$'),
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT, target_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  target_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text CHECK (reason IS NULL OR char_length(reason) <= 500), correlation_id uuid NOT NULL, idempotency_key uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT (metadata::text ~* '(token|email|provider|payload)')),
  CHECK (NOT (target_snapshot::text ~* '(token|email|provider|payload)'))
);
CREATE UNIQUE INDEX administration_events_idempotency_unique ON public.administration_events(actor_user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE public.organisation_invitation_command_receipts (
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  command_kind text NOT NULL CHECK (command_kind IN ('create','resend','revoke','reject','accept')),
  invite_id uuid REFERENCES public.organisation_invites(id) ON DELETE RESTRICT,
  result_code text NOT NULL,
  result_org_id uuid REFERENCES public.organisations(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_user_id, idempotency_key)
);

CREATE OR REPLACE FUNCTION public.invitation_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN NEW.updated_at := now(); IF TG_TABLE_NAME = 'organisation_invites' THEN NEW.revision := OLD.revision + 1; END IF; RETURN NEW; END $$;
CREATE TRIGGER organisation_invites_touch BEFORE UPDATE ON public.organisation_invites FOR EACH ROW EXECUTE FUNCTION public.invitation_touch();
CREATE TRIGGER organisation_invite_deliveries_touch BEFORE UPDATE ON public.organisation_invite_deliveries FOR EACH ROW EXECUTE FUNCTION public.invitation_touch();

-- Preserve eligible legacy states, but remove every raw selector before commit.
INSERT INTO public.organisation_invites (id, org_id, normalized_email, role, state, selector_hash, token_version, expires_at, invited_by_user_id, lifecycle_actor_id, lifecycle_reason, accepted_at, rejected_at, revoked_at, expired_at, created_at, updated_at)
SELECT legacy.id, legacy.org_id, lower(btrim(legacy.invited_email)), legacy.role,
 CASE WHEN legacy.status = 'accepted' THEN 'accepted'::public.organisation_invite_state
      WHEN legacy.status = 'rejected' THEN 'rejected'::public.organisation_invite_state
      WHEN legacy.status = 'expired' OR legacy.expires_at <= now() THEN 'expired'::public.organisation_invite_state
      WHEN legacy.role = 'admin' AND NOT EXISTS (SELECT 1 FROM public.organisations o JOIN public.organisation_memberships m ON m.id=o.owner_membership_id WHERE o.id=legacy.org_id AND m.user_id=legacy.invited_by AND m.state='active') THEN 'revoked'::public.organisation_invite_state
      ELSE 'pending'::public.organisation_invite_state END,
 CASE WHEN legacy.status='pending' AND legacy.expires_at > now() AND (legacy.role <> 'admin' OR EXISTS (SELECT 1 FROM public.organisations o JOIN public.organisation_memberships m ON m.id=o.owner_membership_id WHERE o.id=legacy.org_id AND m.user_id=legacy.invited_by AND m.state='active')) THEN encode(digest(legacy.token, 'sha256'), 'hex') END,
 1, legacy.expires_at, legacy.invited_by, legacy.invited_by,
 CASE WHEN legacy.status='pending' AND legacy.expires_at > now() AND legacy.role='admin' AND NOT EXISTS (SELECT 1 FROM public.organisations o JOIN public.organisation_memberships m ON m.id=o.owner_membership_id WHERE o.id=legacy.org_id AND m.user_id=legacy.invited_by AND m.state='active') THEN 'legacy admin invitation revoked because inviter is not canonical owner' END,
 CASE WHEN legacy.status='accepted' THEN legacy.created_at END, CASE WHEN legacy.status='rejected' THEN legacy.created_at END,
 CASE WHEN legacy.status='pending' AND legacy.expires_at > now() AND legacy.role='admin' AND NOT EXISTS (SELECT 1 FROM public.organisations o JOIN public.organisation_memberships m ON m.id=o.owner_membership_id WHERE o.id=legacy.org_id AND m.user_id=legacy.invited_by AND m.state='active') THEN legacy.created_at END,
 CASE WHEN legacy.status='expired' OR legacy.expires_at <= now() THEN legacy.expires_at END,
 legacy.created_at, legacy.created_at
FROM public.org_invites legacy;

ALTER TABLE public.org_invites ALTER COLUMN token DROP NOT NULL;
UPDATE public.org_invites SET token = NULL;

CREATE OR REPLACE FUNCTION public.invitation_actor(org uuid)
RETURNS TABLE(membership_id uuid, is_owner boolean) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$
 SELECT m.id, o.owner_membership_id=m.id FROM public.organisation_memberships m JOIN public.organisations o ON o.id=m.org_id
 WHERE m.org_id=org AND m.user_id=auth.uid() AND m.state='active' LIMIT 1 $$;

CREATE OR REPLACE FUNCTION public.invitation_event(p_org uuid, p_kind text, p_actor uuid, p_target uuid, p_reason text, p_correlation uuid, p_idempotency uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE inserted_id uuid;
BEGIN
 INSERT INTO public.administration_events(org_id,event_kind,actor_user_id,target_user_id,reason,correlation_id,idempotency_key)
 VALUES(p_org,p_kind,p_actor,p_target,p_reason,p_correlation,p_idempotency)
 ON CONFLICT (actor_user_id,idempotency_key) WHERE idempotency_key IS NOT NULL DO NOTHING RETURNING id INTO inserted_id;
 IF inserted_id IS NULL THEN RETURN false; END IF;
 INSERT INTO public.activity_logs(org_id,user_id,action,entity_type,entity_id,description,metadata)
 VALUES(p_org,p_actor,replace(p_kind,'.v1',''),'organisation',p_org,'Organisation invitation lifecycle updated','{}'::jsonb);
 RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.create_organisation_invite(p_email text,p_role public.org_member_role,p_selector_hash text,p_idempotency_key uuid)
RETURNS TABLE(code text, invite_id uuid, token_version integer, org_name text, inviter_name text, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_org uuid; v_member uuid; v_owner boolean; v_email text:=lower(btrim(p_email)); v_invite uuid; v_retry timestamptz; v_existing public.organisation_invites;
BEGIN
 SELECT m.org_id,a.membership_id,a.is_owner INTO v_org,v_member,v_owner FROM public.organisation_memberships m JOIN LATERAL public.invitation_actor(m.org_id) a ON a.membership_id=m.id LIMIT 1;
 IF v_org IS NULL OR p_email IS NULL OR p_role IS NULL OR p_idempotency_key IS NULL OR p_selector_hash IS NULL OR p_role NOT IN ('associate','viewer','admin') OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR char_length(v_email)>320 OR p_selector_hash !~ '^[0-9a-f]{64}$' THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 IF (p_role='admin' AND NOT v_owner) OR (p_role<>'admin' AND NOT public.has_team_capability(v_org,'team.invite.standard')) THEN RETURN QUERY SELECT 'not_allowed',NULL,NULL,NULL,NULL,NULL; RETURN; END IF;
 SELECT * INTO v_existing FROM public.organisation_invites WHERE invited_by_user_id=auth.uid() AND idempotency_key=p_idempotency_key;
 IF v_existing.id IS NOT NULL THEN RETURN QUERY SELECT 'already_processed',v_existing.id,v_existing.token_version,NULL,NULL,NULL; RETURN; END IF;
 SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.normalized_email=v_email AND d.created_at > now()-interval '24 hours' HAVING count(*) >= 3;
 IF v_retry IS NULL THEN SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries d JOIN public.organisation_invites i ON i.id=d.invite_id WHERE i.org_id=v_org AND d.created_at > now()-interval '24 hours' HAVING count(*) >= 50; END IF;
 IF v_retry IS NOT NULL THEN RETURN QUERY SELECT 'rate_limited',NULL,NULL,NULL,NULL,v_retry; RETURN; END IF;
 IF EXISTS (SELECT 1 FROM auth.users u JOIN public.organisation_memberships m ON m.user_id=u.id WHERE lower(u.email)=v_email AND m.state IN ('active','suspended')) THEN RETURN QUERY SELECT 'not_available',NULL,NULL,NULL,NULL,NULL; RETURN; END IF;
 INSERT INTO public.organisation_invites(org_id,normalized_email,role,selector_hash,invited_by_membership_id,invited_by_user_id,idempotency_key)
 VALUES(v_org,v_email,p_role,p_selector_hash,v_member,auth.uid(),p_idempotency_key) RETURNING id INTO v_invite;
 INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by,idempotency_key) VALUES(v_invite,1,auth.uid(),p_idempotency_key) ON CONFLICT DO NOTHING;
 PERFORM public.invitation_event(v_org,'organisation_invitation.created.v1',auth.uid(),NULL,NULL,(SELECT correlation_id FROM public.organisation_invites WHERE id=v_invite),p_idempotency_key);
 RETURN QUERY SELECT 'created',v_invite,1,o.name,COALESCE(p.display_name,'A team member'),NULL FROM public.organisations o LEFT JOIN public.user_profiles p ON p.user_id=auth.uid() WHERE o.id=v_org;
EXCEPTION WHEN unique_violation THEN RETURN QUERY SELECT 'pending_exists',NULL,NULL,NULL,NULL,NULL; END $$;

DROP FUNCTION IF EXISTS public.resend_organisation_invite(uuid,text,uuid);
CREATE FUNCTION public.resend_organisation_invite(p_invite_id uuid,p_expected_revision bigint,p_selector_hash text,p_idempotency_key uuid)
RETURNS TABLE(code text, invite_id uuid, token_version integer, org_name text, inviter_name text, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE old public.organisation_invites; v_owner boolean; v_new uuid; v_retry timestamptz; v_receipt public.organisation_invitation_command_receipts;
BEGIN
 SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts WHERE actor_user_id=auth.uid() AND idempotency_key=p_idempotency_key;
 IF v_receipt.actor_user_id IS NOT NULL THEN RETURN QUERY SELECT 'already_processed'::text,v_receipt.invite_id,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT * INTO old FROM public.organisation_invites WHERE id=p_invite_id FOR UPDATE; SELECT is_owner INTO v_owner FROM public.invitation_actor(old.org_id);
 IF old.id IS NULL OR p_idempotency_key IS NULL OR p_selector_hash IS NULL OR old.state<>'pending' OR old.revision<>p_expected_revision OR p_selector_hash !~ '^[0-9a-f]{64}$' OR (old.role='admin' AND NOT v_owner) OR (old.role<>'admin' AND NOT public.has_team_capability(old.org_id,'team.invite.standard')) THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.normalized_email=old.normalized_email AND d.created_at>now()-interval '24 hours' HAVING count(*)>=3;
 IF v_retry IS NULL THEN SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries d JOIN public.organisation_invites i ON i.id=d.invite_id WHERE i.org_id=old.org_id AND d.created_at>now()-interval '24 hours' HAVING count(*)>=50; END IF;
 IF v_retry IS NOT NULL THEN RETURN QUERY SELECT 'rate_limited'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,v_retry; RETURN; END IF;
 UPDATE public.organisation_invites SET state='superseded',selector_hash=NULL,superseded_at=now(),lifecycle_actor_id=auth.uid(),superseded_by_id=NULL WHERE id=old.id;
 INSERT INTO public.organisation_invites(org_id,normalized_email,role,selector_hash,token_version,expires_at,invited_by_membership_id,invited_by_user_id,idempotency_key,correlation_id) VALUES(old.org_id,old.normalized_email,old.role,p_selector_hash,old.token_version+1,now()+interval '7 days',old.invited_by_membership_id,auth.uid(),p_idempotency_key,old.correlation_id) RETURNING id INTO v_new;
 UPDATE public.organisation_invites SET superseded_by_id=v_new WHERE id=old.id; INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by,idempotency_key) VALUES(v_new,old.token_version+1,auth.uid(),p_idempotency_key);
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,'resend',v_new,'created',old.org_id);
 PERFORM public.invitation_event(old.org_id,'organisation_invitation.resent.v1',auth.uid(),NULL,NULL,old.correlation_id,p_idempotency_key);
 RETURN QUERY SELECT 'created'::text,v_new,old.token_version+1,o.name,COALESCE(p.display_name,'A team member'),NULL::timestamptz FROM public.organisations o LEFT JOIN public.user_profiles p ON p.user_id=auth.uid() WHERE o.id=old.org_id;
END $$;

CREATE OR REPLACE FUNCTION public.transition_organisation_invite(p_invite_id uuid,p_expected_revision bigint,p_idempotency_key uuid,p_action text,p_reason text DEFAULT NULL)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i public.organisation_invites; v_owner boolean; v_email text;
BEGIN
 IF p_action NOT IN ('reject','revoke') OR p_idempotency_key IS NULL THEN RETURN QUERY SELECT 'not_allowed'; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.organisation_invitation_command_receipts WHERE actor_user_id=auth.uid() AND idempotency_key=p_idempotency_key) THEN RETURN QUERY SELECT 'ok'; RETURN; END IF;
 SELECT * INTO i FROM public.organisation_invites WHERE id=p_invite_id FOR UPDATE; IF i.id IS NULL THEN RETURN QUERY SELECT 'not_available'; RETURN; END IF; SELECT is_owner INTO v_owner FROM public.invitation_actor(i.org_id); SELECT lower(email) INTO v_email FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
 IF p_action='reject' THEN IF v_email IS NULL OR v_email<>i.normalized_email THEN RETURN QUERY SELECT 'not_available'; RETURN; END IF; ELSIF (i.role='admin' AND NOT v_owner) OR (i.role<>'admin' AND NOT public.has_team_capability(i.org_id,'team.invite.standard')) THEN RETURN QUERY SELECT 'not_allowed'; RETURN; END IF;
 IF i.state<> 'pending' THEN RETURN QUERY SELECT 'not_available'; RETURN; END IF;
 IF i.revision<>p_expected_revision THEN RETURN QUERY SELECT 'conflict'; RETURN; END IF;
 IF p_action='reject' THEN UPDATE public.organisation_invites SET state='rejected',selector_hash=NULL,rejected_at=now(),lifecycle_actor_id=auth.uid(),lifecycle_reason=p_reason WHERE id=i.id; ELSE UPDATE public.organisation_invites SET state='revoked',selector_hash=NULL,revoked_at=now(),lifecycle_actor_id=auth.uid(),lifecycle_reason=p_reason WHERE id=i.id; END IF;
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,p_action,i.id,'ok',i.org_id);
 PERFORM public.invitation_event(i.org_id,'organisation_invitation.'||p_action||'.v1',auth.uid(),NULL,p_reason,i.correlation_id,p_idempotency_key); RETURN QUERY SELECT 'ok'; END $$;

CREATE OR REPLACE FUNCTION public.accept_organisation_invite(p_invite_id uuid DEFAULT NULL,p_selector_hash text DEFAULT NULL,p_nonce_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT gen_random_uuid())
RETURNS TABLE(code text, org_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i public.organisation_invites; v_email text; v_membership uuid; v_intent uuid;
BEGIN
 IF p_idempotency_key IS NULL OR ((p_invite_id IS NOT NULL)::int + (p_selector_hash IS NOT NULL)::int + (p_nonce_hash IS NOT NULL)::int) <> 1 THEN RETURN QUERY SELECT 'not_available',NULL::uuid; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.organisation_invitation_command_receipts r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key AND r.command_kind='accept') THEN RETURN QUERY SELECT 'accepted',result_org_id FROM public.organisation_invitation_command_receipts WHERE actor_user_id=auth.uid() AND idempotency_key=p_idempotency_key; RETURN; END IF;
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL; IF v_email IS NULL THEN RETURN QUERY SELECT 'not_available',NULL::uuid; RETURN; END IF;
 IF p_nonce_hash IS NOT NULL THEN SELECT invite_id INTO p_invite_id FROM public.organisation_invitation_accept_intents WHERE nonce_hash=p_nonce_hash AND consumed_at IS NULL AND expires_at>now() FOR UPDATE; END IF;
 IF p_selector_hash IS NOT NULL THEN SELECT * INTO i FROM public.organisation_invites WHERE selector_hash=p_selector_hash AND state='pending' FOR UPDATE; ELSE SELECT * INTO i FROM public.organisation_invites WHERE id=p_invite_id FOR UPDATE; END IF;
 IF i.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF i.state='accepted' AND i.accepted_by_user_id=auth.uid() AND p_invite_id=i.id THEN RETURN QUERY SELECT 'accepted',i.org_id; RETURN; END IF;
 IF i.state<>'pending' OR i.expires_at<=now() OR v_email<>i.normalized_email THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF EXISTS (SELECT 1 FROM public.organisation_memberships AS m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')) THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 INSERT INTO public.org_members(org_id,user_id,role) VALUES(i.org_id,auth.uid(),i.role) ON CONFLICT ON CONSTRAINT org_members_pkey DO NOTHING;
 SELECT id INTO v_membership FROM public.organisation_memberships WHERE org_id=i.org_id AND user_id=auth.uid() AND state='active' ORDER BY generation DESC LIMIT 1;
 IF v_membership IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 UPDATE public.organisation_invites SET state='accepted',selector_hash=NULL,accepted_at=now(),accepted_by_user_id=auth.uid(),accepted_membership_id=v_membership,lifecycle_actor_id=auth.uid() WHERE id=i.id;
 IF p_nonce_hash IS NOT NULL THEN UPDATE public.organisation_invitation_accept_intents SET consumed_at=now() WHERE nonce_hash=p_nonce_hash; END IF;
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,'accept',i.id,'accepted',i.org_id);
 PERFORM public.invitation_event(i.org_id,'organisation_invitation.accepted.v1',auth.uid(),auth.uid(),NULL,i.correlation_id,p_idempotency_key); RETURN QUERY SELECT 'accepted',i.org_id; END $$;

CREATE OR REPLACE FUNCTION public.begin_organisation_invitation_accept_intent(p_selector_hash text,p_nonce_hash text)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i uuid; BEGIN SELECT id INTO i FROM public.organisation_invites WHERE selector_hash=p_selector_hash AND state='pending' AND expires_at>now(); IF i IS NOT NULL AND p_nonce_hash ~ '^[0-9a-f]{64}$' AND (SELECT count(*) FROM public.organisation_invitation_accept_intents WHERE invite_id=i AND created_at>now()-interval '20 minutes') < 5 THEN INSERT INTO public.organisation_invitation_accept_intents(invite_id,nonce_hash,expires_at) VALUES(i,p_nonce_hash,now()+interval '20 minutes') ON CONFLICT (nonce_hash) DO NOTHING; END IF; RETURN QUERY SELECT 'ok'; END $$;

CREATE OR REPLACE FUNCTION public.get_my_pending_organisation_invites()
RETURNS TABLE(id uuid, role public.org_member_role, org_name text, revision bigint) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$
 SELECT i.id,i.role,o.name,i.revision FROM public.organisation_invites i JOIN public.organisations o ON o.id=i.org_id JOIN auth.users u ON u.id=auth.uid() WHERE i.state='pending' AND i.expires_at>now() AND u.email_confirmed_at IS NOT NULL AND i.normalized_email=lower(u.email) $$;
DROP FUNCTION IF EXISTS public.get_organisation_invites();
CREATE FUNCTION public.get_organisation_invites()
RETURNS TABLE(id uuid, role public.org_member_role, state public.organisation_invite_state, created_at timestamptz, expires_at timestamptz, revision bigint, authorized_email text) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$
 SELECT i.id,i.role,i.state,i.created_at,i.expires_at,i.revision,i.normalized_email FROM public.organisation_invites i WHERE public.has_team_capability(i.org_id,'team.invite.standard') $$;
CREATE OR REPLACE FUNCTION public.record_organisation_invite_delivery(p_invite_id uuid,p_state text,p_provider_reference text DEFAULT NULL,p_error_code text DEFAULT NULL)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i public.organisation_invites; d public.organisation_invite_deliveries; command_id uuid; BEGIN SELECT * INTO i FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id; IF i.id IS NULL OR i.invited_by_user_id<>auth.uid() OR p_state NOT IN ('sent','failed') OR p_provider_reference !~ '^[A-Za-z0-9._:-]{1,200}$' OR (p_error_code IS NOT NULL AND p_error_code !~ '^[a-z0-9_.-]{1,80}$') THEN RETURN QUERY SELECT 'not_allowed'::text; RETURN; END IF; SELECT * INTO d FROM public.organisation_invite_deliveries AS od WHERE od.invite_id=i.id AND od.token_version=i.token_version FOR UPDATE; IF d.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF; IF d.state<>'scheduled' THEN RETURN QUERY SELECT 'already_processed'::text; RETURN; END IF; UPDATE public.organisation_invite_deliveries AS od SET state=p_state,sent_at=CASE WHEN p_state='sent' THEN now() ELSE NULL END,failed_at=CASE WHEN p_state='failed' THEN now() ELSE NULL END,provider_reference=p_provider_reference,error_code=p_error_code WHERE od.id=d.id; command_id := ('00000000-0000-0000-0000-' || substr(replace(d.id::text,'-',''),1,12))::uuid; PERFORM public.invitation_event(i.org_id,'organisation_invitation.delivery_recorded.v1',auth.uid(),NULL,NULL,i.correlation_id,command_id); RETURN QUERY SELECT 'ok'::text; END $$;
CREATE OR REPLACE FUNCTION public.maintain_organisation_invitations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN IF current_user <> 'service_role' AND current_user <> 'postgres' THEN RAISE EXCEPTION 'service only'; END IF; UPDATE public.organisation_invites SET state='expired',selector_hash=NULL,expired_at=now(),lifecycle_reason='expiry maintenance' WHERE state='pending' AND expires_at<=now(); UPDATE public.organisation_invites SET normalized_email='redacted-'||id::text||'@invalid.local' WHERE state<>'pending' AND created_at<now()-interval '180 days' AND normalized_email NOT LIKE 'redacted-%'; END $$;

-- Canonical active membership becomes the sole RLS authority.
CREATE OR REPLACE FUNCTION public.is_org_member(check_org_id uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM public.organisation_memberships m WHERE m.org_id=check_org_id AND m.user_id=auth.uid() AND m.state='active') $$;
CREATE OR REPLACE FUNCTION public.is_org_admin(check_org_id uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$ SELECT EXISTS(SELECT 1 FROM public.organisation_memberships m WHERE m.org_id=check_org_id AND m.user_id=auth.uid() AND m.state='active' AND (m.role='admin' OR EXISTS(SELECT 1 FROM public.organisations o WHERE o.id=check_org_id AND o.owner_membership_id=m.id))) $$;
CREATE OR REPLACE FUNCTION public.my_org_ids() RETURNS uuid[] LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public, pg_temp AS $$ SELECT COALESCE(array_agg(m.org_id),ARRAY[]::uuid[]) FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state='active' $$;
DROP POLICY IF EXISTS "org_select" ON public.organisations; CREATE POLICY "org_select_active_member" ON public.organisations FOR SELECT TO authenticated USING (public.is_org_member(id));
DROP POLICY IF EXISTS "members_select" ON public.org_members; DROP POLICY IF EXISTS "members_insert" ON public.org_members; DROP POLICY IF EXISTS "members_update" ON public.org_members; DROP POLICY IF EXISTS "members_delete" ON public.org_members;
CREATE POLICY "members_select_active_directory" ON public.org_members FOR SELECT TO authenticated USING (public.is_org_member(org_id));
DROP POLICY IF EXISTS "invites_select_member" ON public.org_invites; DROP POLICY IF EXISTS "invites_insert" ON public.org_invites; DROP POLICY IF EXISTS "invites_update" ON public.org_invites;
ALTER TABLE public.organisation_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_invite_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_invitation_accept_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.administration_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_invitation_command_receipts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "activity_insert" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_update_reversal" ON public.activity_logs;
REVOKE INSERT, UPDATE, DELETE ON public.activity_logs FROM anon, authenticated, service_role;
GRANT INSERT ON public.activity_logs TO service_role;
CREATE OR REPLACE FUNCTION public.prevent_activity_log_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$ BEGIN RAISE EXCEPTION 'activity logs are append-only'; END $$;
CREATE TRIGGER activity_logs_prevent_mutation BEFORE UPDATE OR DELETE ON public.activity_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_activity_log_mutation();
REVOKE ALL ON FUNCTION public.prevent_activity_log_mutation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.org_invites, public.organisation_invites, public.organisation_invite_deliveries, public.organisation_invitation_accept_intents, public.administration_events, public.organisation_invitation_command_receipts FROM PUBLIC, anon, authenticated;
REVOKE UPDATE, DELETE ON public.administration_events FROM service_role;
REVOKE INSERT, UPDATE, DELETE ON public.org_members FROM authenticated, anon; GRANT SELECT ON public.org_members TO authenticated;
REVOKE ALL ON FUNCTION public.invitation_actor(uuid), public.invitation_event(uuid,text,uuid,uuid,text,uuid,uuid), public.invitation_touch() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid), public.resend_organisation_invite(uuid,bigint,text,uuid), public.transition_organisation_invite(uuid,bigint,uuid,text,text), public.accept_organisation_invite(uuid,text,text,uuid), public.get_my_pending_organisation_invites(), public.get_organisation_invites(), public.record_organisation_invite_delivery(uuid,text,text,text), public.begin_organisation_invitation_accept_intent(text,text), public.maintain_organisation_invitations() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid), public.resend_organisation_invite(uuid,bigint,text,uuid), public.transition_organisation_invite(uuid,bigint,uuid,text,text), public.accept_organisation_invite(uuid,text,text,uuid), public.get_my_pending_organisation_invites(), public.get_organisation_invites(), public.record_organisation_invite_delivery(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.begin_organisation_invitation_accept_intent(text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.maintain_organisation_invitations() TO service_role;
CREATE OR REPLACE VIEW public.organisation_invitation_cutover_diagnostics AS SELECT 'legacy_raw_token_remaining'::text issue_code, id FROM public.org_invites WHERE token IS NOT NULL UNION ALL SELECT 'eligible_pending_without_hash',id FROM public.organisation_invites WHERE state='pending' AND selector_hash IS NULL;
REVOKE ALL ON public.organisation_invitation_cutover_diagnostics FROM PUBLIC, anon, authenticated; GRANT SELECT ON public.organisation_invitation_cutover_diagnostics TO service_role;
DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM public.organisation_identity_cutover_diagnostics) THEN RAISE EXCEPTION 'organisation identity cutover diagnostics are not clean'; END IF;
 IF EXISTS (SELECT 1 FROM public.organisation_invitation_cutover_diagnostics) THEN RAISE EXCEPTION 'organisation invitation cutover diagnostics are not clean'; END IF;
END $$;
COMMIT;
