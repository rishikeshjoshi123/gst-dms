-- Repair routine bodies for databases that already applied 00030.  The
-- definitions are intentionally equivalent to the corrected 00030 contract.
BEGIN;

CREATE OR REPLACE FUNCTION public.create_organisation_invite(p_email text,p_role public.org_member_role,p_selector_hash text,p_idempotency_key uuid)
RETURNS TABLE(code text, invite_id uuid, token_version integer, org_name text, inviter_name text, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_org uuid; v_member uuid; v_owner boolean; v_email text:=lower(btrim(p_email)); v_invite uuid; v_retry timestamptz; v_existing public.organisation_invites;
BEGIN
 SELECT m.org_id,a.membership_id,a.is_owner INTO v_org,v_member,v_owner FROM public.organisation_memberships AS m JOIN LATERAL public.invitation_actor(m.org_id) AS a ON a.membership_id=m.id LIMIT 1;
 IF v_org IS NULL OR p_email IS NULL OR p_role IS NULL OR p_idempotency_key IS NULL OR p_selector_hash IS NULL OR p_role NOT IN ('associate','viewer','admin') OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR char_length(v_email)>320 OR p_selector_hash !~ '^[0-9a-f]{64}$' THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 IF (p_role='admin' AND NOT v_owner) OR (p_role<>'admin' AND NOT public.has_team_capability(v_org,'team.invite.standard')) THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT * INTO v_existing FROM public.organisation_invites AS oi WHERE oi.invited_by_user_id=auth.uid() AND oi.idempotency_key=p_idempotency_key;
 IF v_existing.id IS NOT NULL THEN RETURN QUERY SELECT 'already_processed'::text,v_existing.id,v_existing.token_version,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.normalized_email=v_email AND d.created_at>now()-interval '24 hours' HAVING count(*)>=3;
 IF v_retry IS NULL THEN SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.org_id=v_org AND d.created_at>now()-interval '24 hours' HAVING count(*)>=50; END IF;
 IF v_retry IS NOT NULL THEN RETURN QUERY SELECT 'rate_limited'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,v_retry; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM auth.users AS u JOIN public.organisation_memberships AS m ON m.user_id=u.id WHERE lower(u.email)=v_email AND m.state IN ('active','suspended')) THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 INSERT INTO public.organisation_invites(org_id,normalized_email,role,selector_hash,invited_by_membership_id,invited_by_user_id,idempotency_key) VALUES(v_org,v_email,p_role,p_selector_hash,v_member,auth.uid(),p_idempotency_key) RETURNING id INTO v_invite;
 INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by,idempotency_key) VALUES(v_invite,1,auth.uid(),p_idempotency_key) ON CONFLICT DO NOTHING;
 PERFORM public.invitation_event(v_org,'organisation_invitation.created.v1',auth.uid(),NULL,NULL,(SELECT oi.correlation_id FROM public.organisation_invites AS oi WHERE oi.id=v_invite),p_idempotency_key);
 RETURN QUERY SELECT 'created'::text,v_invite,1,o.name,COALESCE(p.display_name,'A team member'),NULL::timestamptz FROM public.organisations AS o LEFT JOIN public.user_profiles AS p ON p.user_id=auth.uid() WHERE o.id=v_org;
EXCEPTION WHEN unique_violation THEN RETURN QUERY SELECT 'pending_exists'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; END $$;

CREATE OR REPLACE FUNCTION public.accept_organisation_invite(p_invite_id uuid DEFAULT NULL,p_selector_hash text DEFAULT NULL,p_nonce_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT gen_random_uuid())
RETURNS TABLE(code text, org_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_invite public.organisation_invites; v_email text; v_membership uuid;
BEGIN
 IF p_idempotency_key IS NULL OR ((p_invite_id IS NOT NULL)::int+(p_selector_hash IS NOT NULL)::int+(p_nonce_hash IS NOT NULL)::int)<>1 THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.organisation_invitation_command_receipts AS r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key AND r.command_kind='accept') THEN RETURN QUERY SELECT 'accepted'::text,r.result_org_id FROM public.organisation_invitation_command_receipts AS r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key; RETURN; END IF;
 SELECT lower(u.email) INTO v_email FROM auth.users AS u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL; IF v_email IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF p_nonce_hash IS NOT NULL THEN SELECT ai.invite_id INTO p_invite_id FROM public.organisation_invitation_accept_intents AS ai WHERE ai.nonce_hash=p_nonce_hash AND ai.consumed_at IS NULL AND ai.expires_at>now() FOR UPDATE; END IF;
 IF p_selector_hash IS NOT NULL THEN SELECT * INTO v_invite FROM public.organisation_invites AS oi WHERE oi.selector_hash=p_selector_hash AND oi.state='pending' FOR UPDATE; ELSE SELECT * INTO v_invite FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id FOR UPDATE; END IF;
 IF v_invite.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF v_invite.state='accepted' AND v_invite.accepted_by_user_id=auth.uid() AND p_invite_id=v_invite.id THEN RETURN QUERY SELECT 'accepted'::text,v_invite.org_id; RETURN; END IF;
 IF v_invite.state<>'pending' OR v_invite.expires_at<=now() OR v_email<>v_invite.normalized_email OR EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')) THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 INSERT INTO public.org_members(org_id,user_id,role) VALUES(v_invite.org_id,auth.uid(),v_invite.role) ON CONFLICT ON CONSTRAINT org_members_pkey DO NOTHING;
 SELECT m.id INTO v_membership FROM public.organisation_memberships AS m WHERE m.org_id=v_invite.org_id AND m.user_id=auth.uid() AND m.state='active' ORDER BY m.generation DESC LIMIT 1;
 IF v_membership IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 UPDATE public.organisation_invites AS oi SET state='accepted',selector_hash=NULL,accepted_at=now(),accepted_by_user_id=auth.uid(),accepted_membership_id=v_membership,lifecycle_actor_id=auth.uid() WHERE oi.id=v_invite.id;
 IF p_nonce_hash IS NOT NULL THEN UPDATE public.organisation_invitation_accept_intents AS ai SET consumed_at=now() WHERE ai.nonce_hash=p_nonce_hash; END IF;
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,'accept',v_invite.id,'accepted',v_invite.org_id);
 PERFORM public.invitation_event(v_invite.org_id,'organisation_invitation.accepted.v1',auth.uid(),auth.uid(),NULL,v_invite.correlation_id,p_idempotency_key);
 RETURN QUERY SELECT 'accepted'::text,v_invite.org_id;
END $$;

REVOKE ALL ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid), public.accept_organisation_invite(uuid,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_organisation_invite(text,public.org_member_role,text,uuid), public.accept_organisation_invite(uuid,text,text,uuid) TO authenticated;
COMMIT;
