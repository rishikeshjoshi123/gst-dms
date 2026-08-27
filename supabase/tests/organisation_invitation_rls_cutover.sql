-- Disposable local database only; deterministic fixtures and no persistent state.
BEGIN;
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000001','authenticated','authenticated','owner@invite.example.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000002','authenticated','authenticated','join@invite.example.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000003','authenticated','authenticated','wrong@invite.example.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES('32000000-0000-0000-0000-000000000001','Invitation fixture','31000000-0000-0000-0000-000000000001');
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000004','authenticated','authenticated','admin@invite.example.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000005','authenticated','authenticated','other@invite.example.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000006','authenticated','authenticated','suspended@invite.example.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','31000000-0000-0000-0000-000000000007','authenticated','authenticated','removed@invite.example.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.org_members(org_id,user_id,role) VALUES('32000000-0000-0000-0000-000000000001','31000000-0000-0000-0000-000000000004','admin');
DO $t$
DECLARE r record; i uuid; n uuid; rev bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM public.organisation_identity_cutover_diagnostics) OR EXISTS(SELECT 1 FROM public.organisation_invitation_cutover_diagnostics) OR EXISTS(SELECT 1 FROM public.org_invites WHERE token IS NOT NULL) THEN RAISE EXCEPTION 'cutover diagnostics failed'; END IF;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
 SELECT * INTO r FROM public.create_organisation_invite('join@invite.example.test','associate',repeat('a',64),'41000000-0000-0000-0000-000000000001'); IF r.code<>'created' THEN RAISE EXCEPTION 'create %',r.code; END IF; i:=r.invite_id;
 SELECT * INTO r FROM public.create_organisation_invite('join@invite.example.test','associate',repeat('b',64),'41000000-0000-0000-0000-000000000001'); IF r.code<>'already_processed' THEN RAISE EXCEPTION 'create retry'; END IF;
 SELECT * INTO r FROM public.create_organisation_invite('join@invite.example.test','associate',repeat('b',64),'41000000-0000-0000-0000-000000000002'); IF r.code<>'pending_exists' THEN RAISE EXCEPTION 'pending duplicate'; END IF;
 SELECT revision INTO rev FROM public.organisation_invites WHERE id=i;
 SELECT * INTO r FROM public.resend_organisation_invite(i,rev,repeat('c',64),'41000000-0000-0000-0000-000000000003'); IF r.code<>'created' THEN RAISE EXCEPTION 'resend %',r.code; END IF; n:=r.invite_id;
 IF EXISTS(SELECT 1 FROM public.organisation_invites WHERE id=i AND state='pending') OR NOT EXISTS(SELECT 1 FROM public.organisation_invites WHERE id=n AND selector_hash=repeat('c',64)) THEN RAISE EXCEPTION 'rotation'; END IF;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000003',true); SELECT * INTO r FROM public.accept_organisation_invite(NULL,repeat('c',64),NULL,'41000000-0000-0000-0000-000000000004'); IF r.code<>'not_available' THEN RAISE EXCEPTION 'email mismatch'; END IF;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000002',true); SELECT * INTO r FROM public.accept_organisation_invite(NULL,repeat('c',64),NULL,'41000000-0000-0000-0000-000000000005'); IF r.code<>'accepted' THEN RAISE EXCEPTION 'accept'; END IF;
 SELECT * INTO r FROM public.accept_organisation_invite(n,NULL,NULL,'41000000-0000-0000-0000-000000000005'); IF r.code<>'accepted' THEN RAISE EXCEPTION 'accept retry'; END IF;
 IF (SELECT count(*) FROM public.administration_events WHERE event_kind='organisation_invitation.accepted.v1')<>1 OR EXISTS(SELECT 1 FROM public.administration_events WHERE metadata::text ~* '(token|email|provider|payload)') THEN RAISE EXCEPTION 'ledger'; END IF;
END $t$;

-- B/C/D: delivery state, rate, resend and transition matrix.
DO $lifecycle$
DECLARE r record; v_delivery_invite_id uuid; v_admin_invite uuid; v_revision bigint; event_count int; activity_count int; x int;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
 SELECT * INTO r FROM public.create_organisation_invite('delivery@invite.example.test','viewer',repeat('d',64),'42000000-0000-0000-0000-000000000001'); v_delivery_invite_id:=r.invite_id;
 IF r.code<>'created' THEN RAISE EXCEPTION 'delivery fixture create'; END IF;
 SELECT * INTO r FROM public.record_organisation_invite_delivery(v_delivery_invite_id,'sent','provider-safe_1',NULL); IF r.code<>'ok' OR NOT EXISTS(SELECT 1 FROM public.organisation_invite_deliveries AS od WHERE od.invite_id=v_delivery_invite_id AND od.state='sent' AND od.sent_at IS NOT NULL AND od.failed_at IS NULL) OR NOT EXISTS(SELECT 1 FROM public.administration_events AS ae WHERE ae.event_kind='organisation_invitation.delivered.v1') THEN RAISE EXCEPTION 'sent delivery state'; END IF;
 SELECT count(*) INTO event_count FROM public.administration_events AS ae WHERE ae.event_kind='organisation_invitation.delivered.v1'; SELECT * INTO r FROM public.record_organisation_invite_delivery(v_delivery_invite_id,'sent','provider-safe_1',NULL); IF r.code<>'already_processed' OR (SELECT count(*) FROM public.administration_events AS ae WHERE ae.event_kind='organisation_invitation.delivered.v1')<>event_count THEN RAISE EXCEPTION 'delivery retry ledger'; END IF;
 SELECT * INTO r FROM public.create_organisation_invite('failed@invite.example.test','viewer',repeat('e',64),'42000000-0000-0000-0000-000000000002');
 SELECT * INTO r FROM public.record_organisation_invite_delivery(r.invite_id,'failed','provider-safe_2','delivery_failed'); IF r.code<>'ok' OR NOT EXISTS(SELECT 1 FROM public.organisation_invite_deliveries AS od WHERE od.state='failed' AND od.failed_at IS NOT NULL AND od.sent_at IS NULL AND od.error_code='delivery_failed') OR NOT EXISTS(SELECT 1 FROM public.administration_events WHERE event_kind='organisation_invitation.delivery_failed.v1') THEN RAISE EXCEPTION 'failed delivery state'; END IF;
 IF EXISTS(SELECT 1 FROM public.administration_events e WHERE e.metadata::text ~* '(token|email|provider|payload)') OR EXISTS(SELECT 1 FROM public.activity_logs a WHERE a.metadata::text ~* '(token|email|provider|payload)') THEN RAISE EXCEPTION 'secret ledger payload'; END IF;
 -- Address limit is exercised with three historical scheduled deliveries, then a fourth command.
 FOR x IN 1..3 LOOP
   INSERT INTO public.organisation_invites(org_id,normalized_email,role,state,selector_hash,expires_at,invited_by_user_id) VALUES('32000000-0000-0000-0000-000000000001','limit@invite.example.test','viewer','pending',lpad(x::text,64,'0'),now()+interval '1 day','31000000-0000-0000-0000-000000000001') RETURNING id INTO v_delivery_invite_id;
   INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by) VALUES(v_delivery_invite_id,1,'31000000-0000-0000-0000-000000000001');
   UPDATE public.organisation_invites AS oi SET state='revoked',selector_hash=NULL,revoked_at=now() WHERE oi.id=v_delivery_invite_id;
 END LOOP;
 SELECT * INTO r FROM public.create_organisation_invite('limit@invite.example.test','viewer',repeat('f',64),'42000000-0000-0000-0000-000000000010'); IF r.code<>'rate_limited' OR r.retry_after IS NULL THEN RAISE EXCEPTION 'address rate boundary'; END IF;
 -- Aggregate boundary is deterministic without relying on provider delivery.
 FOR x IN 1..50 LOOP
   INSERT INTO public.organisation_invites(org_id,normalized_email,role,state,selector_hash,expires_at,invited_by_user_id) VALUES('32000000-0000-0000-0000-000000000001','org'||x||'@invite.example.test','viewer','pending',lpad((x+100)::text,64,'0'),now()+interval '1 day','31000000-0000-0000-0000-000000000001') RETURNING id INTO v_delivery_invite_id;
   INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,created_by) VALUES(v_delivery_invite_id,1,'31000000-0000-0000-0000-000000000001');
 END LOOP;
 SELECT * INTO r FROM public.create_organisation_invite('org51@invite.example.test','viewer',repeat('9',64),'42000000-0000-0000-0000-000000000011'); IF r.code<>'rate_limited' OR r.retry_after IS NULL THEN RAISE EXCEPTION 'organisation rate boundary'; END IF;
 -- Owner may revoke Admin; an ordinary Admin may not revoke Admin, while a Standard invite is revocable.
 UPDATE public.organisation_invite_deliveries AS od SET created_at=now()-interval '25 hours' WHERE od.created_at>now()-interval '1 hour';
 INSERT INTO public.organisation_invites(org_id,normalized_email,role,state,selector_hash,expires_at,invited_by_user_id) VALUES('32000000-0000-0000-0000-000000000001','admin-target@invite.example.test','admin','pending',repeat('8',64),now()+interval '1 day','31000000-0000-0000-0000-000000000001') RETURNING id,revision INTO v_admin_invite,v_revision;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000004',true); SELECT * INTO r FROM public.transition_organisation_invite(v_admin_invite,v_revision,'42000000-0000-0000-0000-000000000012','revoke',NULL); IF r.code<>'not_allowed' THEN RAISE EXCEPTION 'non-owner admin revocation'; END IF;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true); SELECT * INTO r FROM public.transition_organisation_invite(v_admin_invite,v_revision,'42000000-0000-0000-0000-000000000013','revoke','test'); IF r.code<>'ok' THEN RAISE EXCEPTION 'owner admin revoke'; END IF;
 SELECT count(*) INTO event_count FROM public.administration_events; SELECT count(*) INTO activity_count FROM public.activity_logs WHERE action LIKE 'organisation_invitation.%'; IF event_count<>activity_count THEN RAISE EXCEPTION 'event/activity parity'; END IF;
END $lifecycle$;

-- E/F/G: opaque intent binding and privacy/grant assertions.
DO $security$
DECLARE r record; intent_invite uuid; before_count int;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000001',true);
 SELECT * INTO r FROM public.create_organisation_invite('removed@invite.example.test','viewer',repeat('7',64),'43000000-0000-0000-0000-000000000001'); intent_invite:=r.invite_id;
 FOR before_count IN 1..6 LOOP PERFORM * FROM public.begin_organisation_invitation_accept_intent(repeat('7',64),lpad((before_count+400)::text,64,'0')); END LOOP;
 IF (SELECT count(*) FROM public.organisation_invitation_accept_intents ai WHERE ai.invite_id=intent_invite)<=0 OR (SELECT count(*) FROM public.organisation_invitation_accept_intents ai WHERE ai.invite_id=intent_invite)>5 THEN RAISE EXCEPTION 'intent cap'; END IF;
 UPDATE public.organisation_invitation_accept_intents SET created_at=now()-interval '21 minutes', expires_at=now()-interval '1 minute' WHERE invite_id=intent_invite;
 PERFORM set_config('request.jwt.claim.sub','31000000-0000-0000-0000-000000000007',true); SELECT * INTO r FROM public.accept_organisation_invite(NULL,NULL,lpad(401::text,64,'0'),'43000000-0000-0000-0000-000000000002'); IF r.code<>'not_available' THEN RAISE EXCEPTION 'expired intent'; END IF;
 IF EXISTS(SELECT 1 FROM public.get_organisation_invites() WHERE authorized_email IS NULL) THEN RAISE EXCEPTION 'admin invite projection'; END IF;
 IF NOT has_function_privilege('authenticated','public.create_organisation_invite(text,public.org_member_role,text,uuid)','EXECUTE') OR has_function_privilege('authenticated','public.invitation_actor(uuid)','EXECUTE') OR has_function_privilege('authenticated','public.prevent_activity_log_mutation()','EXECUTE') THEN RAISE EXCEPTION 'RPC grant surface'; END IF;
END $security$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN BEGIN PERFORM public.invitation_actor('32000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'internal execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; BEGIN INSERT INTO public.organisation_invites(org_id,normalized_email,role,selector_hash) VALUES('32000000-0000-0000-0000-000000000001','direct@example.test','viewer',repeat('0',64)); RAISE EXCEPTION 'direct mutation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; BEGIN INSERT INTO public.activity_logs(org_id,action,entity_type) VALUES('32000000-0000-0000-0000-000000000001','forged','organisation'); RAISE EXCEPTION 'direct activity insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; BEGIN UPDATE public.activity_logs SET action='forged' WHERE false; RAISE EXCEPTION 'direct activity update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; BEGIN DELETE FROM public.activity_logs WHERE false; RAISE EXCEPTION 'direct activity delete'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
RESET ROLE;
ROLLBACK;
