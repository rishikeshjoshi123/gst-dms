-- Forward-only repair for 00030/00031 environments.
BEGIN;
DROP POLICY IF EXISTS "activity_insert" ON public.activity_logs;
DROP POLICY IF EXISTS "activity_update_reversal" ON public.activity_logs;
REVOKE INSERT, UPDATE, DELETE ON public.activity_logs FROM anon, authenticated, service_role;
GRANT INSERT ON public.activity_logs TO service_role;
CREATE OR REPLACE FUNCTION public.prevent_activity_log_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$ BEGIN RAISE EXCEPTION 'activity logs are append-only'; END $$;
DROP TRIGGER IF EXISTS activity_logs_prevent_mutation ON public.activity_logs;
CREATE TRIGGER activity_logs_prevent_mutation BEFORE UPDATE OR DELETE ON public.activity_logs FOR EACH ROW EXECUTE FUNCTION public.prevent_activity_log_mutation();
REVOKE ALL ON FUNCTION public.prevent_activity_log_mutation() FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.resend_organisation_invite(p_invite_id uuid,p_expected_revision bigint,p_selector_hash text,p_idempotency_key uuid)
RETURNS TABLE(code text, invite_id uuid, token_version integer, org_name text, inviter_name text, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE old public.organisation_invites; v_owner boolean; v_new uuid; v_retry timestamptz; v_receipt public.organisation_invitation_command_receipts;
BEGIN
 SELECT * INTO v_receipt FROM public.organisation_invitation_command_receipts AS r WHERE r.actor_user_id=auth.uid() AND r.idempotency_key=p_idempotency_key;
 IF v_receipt.actor_user_id IS NOT NULL THEN RETURN QUERY SELECT 'already_processed'::text,v_receipt.invite_id,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT * INTO old FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id FOR UPDATE; SELECT a.is_owner INTO v_owner FROM public.invitation_actor(old.org_id) AS a;
 IF old.id IS NULL OR p_idempotency_key IS NULL OR p_selector_hash IS NULL OR old.state<>'pending' OR old.revision<>p_expected_revision OR p_selector_hash !~ '^[0-9a-f]{64}$' OR (old.role='admin' AND NOT v_owner) OR (old.role<>'admin' AND NOT public.has_team_capability(old.org_id,'team.invite.standard')) THEN RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,NULL::timestamptz; RETURN; END IF;
 SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.normalized_email=old.normalized_email AND d.created_at>now()-interval '24 hours' HAVING count(*)>=3;
 IF v_retry IS NULL THEN SELECT min(d.created_at)+interval '24 hours' INTO v_retry FROM public.organisation_invite_deliveries AS d JOIN public.organisation_invites AS i ON i.id=d.invite_id WHERE i.org_id=old.org_id AND d.created_at>now()-interval '24 hours' HAVING count(*)>=50; END IF;
 IF v_retry IS NOT NULL THEN RETURN QUERY SELECT 'rate_limited'::text,NULL::uuid,NULL::integer,NULL::text,NULL::text,v_retry; RETURN; END IF;
 UPDATE public.organisation_invites AS oi SET state='superseded',selector_hash=NULL,superseded_at=now(),lifecycle_actor_id=auth.uid(),superseded_by_id=NULL WHERE oi.id=old.id;
 INSERT INTO public.organisation_invites(org_id,normalized_email,role,selector_hash,token_version,expires_at,invited_by_membership_id,invited_by_user_id,idempotency_key,correlation_id) VALUES(old.org_id,old.normalized_email,old.role,p_selector_hash,old.token_version+1,now()+interval '7 days',old.invited_by_membership_id,auth.uid(),p_idempotency_key,old.correlation_id) RETURNING id INTO v_new;
 UPDATE public.organisation_invites AS oi SET superseded_by_id=v_new WHERE oi.id=old.id; INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by,idempotency_key) VALUES(v_new,old.token_version+1,auth.uid(),p_idempotency_key);
 INSERT INTO public.organisation_invitation_command_receipts(actor_user_id,idempotency_key,command_kind,invite_id,result_code,result_org_id) VALUES(auth.uid(),p_idempotency_key,'resend',v_new,'created',old.org_id); PERFORM public.invitation_event(old.org_id,'organisation_invitation.resent.v1',auth.uid(),NULL,NULL,old.correlation_id,p_idempotency_key);
 RETURN QUERY SELECT 'created'::text,v_new,old.token_version+1,o.name,COALESCE(p.display_name,'A team member'),NULL::timestamptz FROM public.organisations AS o LEFT JOIN public.user_profiles AS p ON p.user_id=auth.uid() WHERE o.id=old.org_id;
END $$;

CREATE OR REPLACE FUNCTION public.record_organisation_invite_delivery(p_invite_id uuid,p_state text,p_provider_reference text DEFAULT NULL,p_error_code text DEFAULT NULL)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE i public.organisation_invites; d public.organisation_invite_deliveries; command_id uuid;
BEGIN
 SELECT * INTO i FROM public.organisation_invites AS oi WHERE oi.id=p_invite_id; IF i.id IS NULL OR i.invited_by_user_id<>auth.uid() OR p_state NOT IN ('sent','failed') OR p_provider_reference !~ '^[A-Za-z0-9._:-]{1,200}$' OR (p_error_code IS NOT NULL AND p_error_code !~ '^[a-z0-9_.-]{1,80}$') THEN RETURN QUERY SELECT 'not_allowed'::text; RETURN; END IF;
 SELECT * INTO d FROM public.organisation_invite_deliveries AS od WHERE od.invite_id=i.id AND od.token_version=i.token_version FOR UPDATE; IF d.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF; IF d.state<>'scheduled' THEN RETURN QUERY SELECT 'already_processed'::text; RETURN; END IF;
 UPDATE public.organisation_invite_deliveries AS od SET state=p_state,sent_at=CASE WHEN p_state='sent' THEN now() ELSE NULL END,failed_at=CASE WHEN p_state='failed' THEN now() ELSE NULL END,provider_reference=p_provider_reference,error_code=p_error_code WHERE od.id=d.id;
 command_id := ('00000000-0000-0000-0000-' || substr(replace(d.id::text,'-',''),1,12))::uuid;
 PERFORM public.invitation_event(i.org_id,CASE WHEN p_state='sent' THEN 'organisation_invitation.delivered.v1' ELSE 'organisation_invitation.delivery_failed.v1' END,auth.uid(),NULL,NULL,i.correlation_id,command_id);
 RETURN QUERY SELECT 'ok'::text;
END $$;
GRANT EXECUTE ON FUNCTION public.resend_organisation_invite(uuid,bigint,text,uuid), public.record_organisation_invite_delivery(uuid,text,text,text) TO authenticated;
COMMIT;
