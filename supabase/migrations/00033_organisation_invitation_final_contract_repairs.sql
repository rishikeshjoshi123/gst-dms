-- Final privilege repair for databases with 00030--00032 in their ledger.
BEGIN;
CREATE OR REPLACE FUNCTION public.accept_organisation_invite(p_invite_id uuid DEFAULT NULL,p_selector_hash text DEFAULT NULL,p_nonce_hash text DEFAULT NULL,p_idempotency_key uuid DEFAULT gen_random_uuid())
RETURNS TABLE(code text, org_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_invite public.organisation_invites; v_email text; v_membership uuid;
BEGIN
 IF p_idempotency_key IS NULL OR ((p_invite_id IS NOT NULL)::int+(p_selector_hash IS NOT NULL)::int+(p_nonce_hash IS NOT NULL)::int)<>1 THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.organisation_invitation_command_receipts AS r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key AND r.command_kind='accept') THEN RETURN QUERY SELECT 'accepted'::text,r.result_org_id FROM public.organisation_invitation_command_receipts AS r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key; RETURN; END IF;
 SELECT lower(u.email) INTO v_email FROM auth.users AS u WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL;
 IF v_email IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF p_nonce_hash IS NOT NULL THEN SELECT ai.invite_id INTO p_invite_id FROM public.organisation_invitation_accept_intents AS ai WHERE ai.nonce_hash=p_nonce_hash AND ai.consumed_at IS NULL AND ai.expires_at>now() FOR UPDATE; END IF;
 IF p_selector_hash IS NOT NULL THEN SELECT * INTO v_invite FROM public.organisation_invites AS oi WHERE oi.selector_hash=p_selector_hash AND oi.state='pending' FOR UPDATE; ELSE SELECT * INTO v_invite FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id FOR UPDATE; END IF;
 IF v_invite.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 IF v_invite.state='accepted' AND v_invite.accepted_by_user_id=auth.uid() AND p_invite_id=v_invite.id THEN RETURN QUERY SELECT 'accepted'::text,v_invite.org_id; RETURN; END IF;
 IF v_invite.state<>'pending' OR v_invite.expires_at<=now() OR v_email<>v_invite.normalized_email THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 -- A removed historical generation is deliberately eligible; active/suspended
 -- current membership is not, including in this organisation.
 IF EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')) THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 INSERT INTO public.org_members(org_id,user_id,role) VALUES(v_invite.org_id,auth.uid(),v_invite.role) ON CONFLICT ON CONSTRAINT org_members_pkey DO NOTHING;
 SELECT m.id INTO v_membership FROM public.organisation_memberships AS m WHERE m.org_id=v_invite.org_id AND m.user_id=auth.uid() AND m.state='active' ORDER BY m.generation DESC LIMIT 1;
 IF v_membership IS NULL THEN RETURN QUERY SELECT 'not_available'::text,NULL::uuid; RETURN; END IF;
 UPDATE public.organisation_invites AS oi SET state='accepted',selector_hash=NULL,accepted_at=now(),accepted_by_user_id=auth.uid(),accepted_membership_id=v_membership,lifecycle_actor_id=auth.uid() WHERE oi.id=v_invite.id;
 IF p_nonce_hash IS NOT NULL THEN UPDATE public.organisation_invitation_accept_intents AS ai SET consumed_at=now() WHERE ai.nonce_hash=p_nonce_hash; END IF;
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,'accept',v_invite.id,'accepted',v_invite.org_id);
 PERFORM public.invitation_event(v_invite.org_id,'organisation_invitation.accepted.v1',auth.uid(),auth.uid(),NULL,v_invite.correlation_id,p_idempotency_key);
 RETURN QUERY SELECT 'accepted'::text,v_invite.org_id;
END $$;

CREATE OR REPLACE FUNCTION public.record_organisation_invite_delivery(p_invite_id uuid,p_state text,p_provider_reference text DEFAULT NULL,p_error_code text DEFAULT NULL)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i public.organisation_invites; d public.organisation_invite_deliveries; command_id uuid;
BEGIN
 SELECT * INTO i FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id;
 IF i.id IS NULL OR i.invited_by_user_id<>auth.uid() OR p_state NOT IN ('sent','failed') OR p_provider_reference !~ '^[A-Za-z0-9._:-]{1,200}$' OR (p_error_code IS NOT NULL AND p_error_code !~ '^[a-z0-9_.-]{1,80}$') THEN RETURN QUERY SELECT 'not_allowed'::text; RETURN; END IF;
 SELECT * INTO d FROM public.organisation_invite_deliveries AS od WHERE od.invite_id=i.id AND od.token_version=i.token_version FOR UPDATE;
 IF d.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF;
 IF d.state<>'scheduled' THEN RETURN QUERY SELECT 'already_processed'::text; RETURN; END IF;
 UPDATE public.organisation_invite_deliveries AS od SET state=p_state,sent_at=CASE WHEN p_state='sent' THEN now() ELSE NULL END,failed_at=CASE WHEN p_state='failed' THEN now() ELSE NULL END,provider_reference=p_provider_reference,error_code=p_error_code WHERE od.id=d.id;
 command_id := ('00000000-0000-0000-0000-' || substr(replace(d.id::text,'-',''),1,12))::uuid;
 PERFORM public.invitation_event(i.org_id,CASE WHEN p_state='sent' THEN 'organisation_invitation.delivered.v1' ELSE 'organisation_invitation.delivery_failed.v1' END,auth.uid(),NULL,NULL,i.correlation_id,command_id);
 RETURN QUERY SELECT 'ok'::text;
END $$;

REVOKE ALL ON FUNCTION public.prevent_activity_log_mutation() FROM PUBLIC, anon, authenticated;
-- 00032 owns the corrected runtime routine bodies; repeat its public surface.
REVOKE ALL ON FUNCTION public.record_organisation_invite_delivery(uuid,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.accept_organisation_invite(uuid,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_organisation_invite_delivery(uuid,text,text,text), public.accept_organisation_invite(uuid,text,text,uuid) TO authenticated;
COMMIT;
