-- D15-T02 governed invitation administration. Disposable and rollback-only.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000001','authenticated','authenticated','owner@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000002','authenticated','authenticated','admin@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000003','authenticated','authenticated','associate@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000005','authenticated','authenticated','joiner@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@invite.test','x',now(),'{}','{}',now(),now()),
('00000000-0000-0000-0000-000000000000','16000000-0000-0000-0000-000000000007','authenticated','authenticated','suspended@invite.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES
('16100000-0000-0000-0000-000000000001','Invitation fixture','16000000-0000-0000-0000-000000000001'),
('16100000-0000-0000-0000-000000000002','Foreign fixture','16000000-0000-0000-0000-000000000006');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
('16100000-0000-0000-0000-000000000001','16000000-0000-0000-0000-000000000002','admin'),
('16100000-0000-0000-0000-000000000001','16000000-0000-0000-0000-000000000003','associate'),
('16100000-0000-0000-0000-000000000001','16000000-0000-0000-0000-000000000004','viewer'),
('16100000-0000-0000-0000-000000000001','16000000-0000-0000-0000-000000000007','viewer');
UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='16000000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE user_id='16000000-0000-0000-0000-000000000007';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000001',true);
DO $owner$
DECLARE standard record; privileged record; duplicate record; active_recipient record; suspended_recipient record;
BEGIN
 SELECT * INTO standard FROM public.create_organisation_invite(' Joiner@Invite.Test ','associate',repeat('a',64),'16200000-0000-0000-0000-000000000001');
 SELECT * INTO privileged FROM public.create_organisation_invite('admin-new@invite.test','admin',repeat('b',64),'16200000-0000-0000-0000-000000000002');
 SELECT * INTO duplicate FROM public.create_organisation_invite('joiner@invite.test','viewer',repeat('c',64),'16200000-0000-0000-0000-000000000003');
 SELECT * INTO active_recipient FROM public.create_organisation_invite('admin@invite.test','viewer',repeat('6',64),'16200000-0000-0000-0000-000000000015');
 SELECT * INTO suspended_recipient FROM public.create_organisation_invite('suspended@invite.test','viewer',repeat('7',64),'16200000-0000-0000-0000-000000000016');
 IF standard.code<>'created' OR privileged.code<>'created' OR duplicate.code<>'pending_exists'
    OR active_recipient.code<>'not_available' OR suspended_recipient.code<>'not_available' THEN RAISE EXCEPTION 'Owner create/normalization/duplicate/existing-member contract failed'; END IF;
 IF (SELECT count(*) FROM public.get_organisation_invites())<>2 OR EXISTS(SELECT 1 FROM public.get_organisation_invites() WHERE authorized_email<>lower(authorized_email)) THEN RAISE EXCEPTION 'pending projection failed'; END IF;
END $owner$;

SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000002',true);
DO $admin$
DECLARE denied record; allowed record; target record; resent record;
BEGIN
 SELECT * INTO denied FROM public.create_organisation_invite('another-admin@invite.test','admin',repeat('d',64),'16200000-0000-0000-0000-000000000004');
 SELECT * INTO allowed FROM public.create_organisation_invite('viewer-new@invite.test','viewer',repeat('e',64),'16200000-0000-0000-0000-000000000005');
 SELECT * INTO target FROM public.get_organisation_invites() WHERE id=allowed.invite_id;
 SELECT * INTO resent FROM public.resend_organisation_invite(target.id,target.revision,repeat('f',64),'16200000-0000-0000-0000-000000000006');
 IF denied.code<>'not_allowed' OR allowed.code<>'created' OR resent.code<>'created' OR resent.invite_id=target.id THEN RAISE EXCEPTION 'Admin role or resend contract failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.get_organisation_invites('superseded') WHERE id=target.id)
    OR NOT EXISTS(SELECT 1 FROM public.get_organisation_invites() WHERE id=resent.invite_id AND expires_at>clock_timestamp()+interval '6 days 23 hours') THEN RAISE EXCEPTION 'resend did not rotate and extend'; END IF;
END $admin$;

SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000001',true);
DO $revoke$
DECLARE target record; outcome record; mismatch record;
BEGIN
 SELECT * INTO target FROM public.get_organisation_invites() WHERE authorized_email='admin-new@invite.test';
 SELECT * INTO outcome FROM public.transition_organisation_invite(target.id,target.revision,'16200000-0000-0000-0000-000000000012','revoke','  No longer required  ');
 SELECT * INTO mismatch FROM public.transition_organisation_invite(target.id,target.revision,'16200000-0000-0000-0000-000000000012','revoke','Different reason');
 IF outcome.code<>'ok' OR mismatch.code<>'idempotency_subject_mismatch' OR NOT EXISTS(SELECT 1 FROM public.get_organisation_invites('revoked') WHERE id=target.id) THEN RAISE EXCEPTION 'Owner revoke/reason-bound replay failed'; END IF;
END $revoke$;

RESET ROLE;
INSERT INTO public.organisation_invites(id,org_id,normalized_email,role,state,selector_hash,invited_by_user_id,lifecycle_actor_id,idempotency_key,expires_at,revoked_at)
SELECT ('16300000-0000-0000-0000-'||lpad(series::text,12,'0'))::uuid,'16100000-0000-0000-0000-000000000001',
  CASE WHEN series<=3 THEN 'limited@invite.test' ELSE 'org-limit-'||series||'@invite.test' END,
  'viewer','revoked',NULL,'16000000-0000-0000-0000-000000000001','16000000-0000-0000-0000-000000000001',
  ('16400000-0000-0000-0000-'||lpad(series::text,12,'0'))::uuid,now()+interval '1 day',now()
FROM generate_series(1,47) AS series;
INSERT INTO public.organisation_invite_deliveries(invite_id,token_version,state,created_by,idempotency_key,sent_at)
SELECT invitation.id,1,'sent','16000000-0000-0000-0000-000000000001',gen_random_uuid(),now()
FROM public.organisation_invites AS invitation WHERE invitation.id::text LIKE '16300000-0000-0000-0000-%';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000001',true);
DO $rate_limits$
DECLARE address_limited record; org_limited record;
BEGIN
 SELECT * INTO address_limited FROM public.create_organisation_invite('limited@invite.test','viewer',repeat('4',64),'16200000-0000-0000-0000-000000000013');
 SELECT * INTO org_limited FROM public.create_organisation_invite('fresh@invite.test','viewer',repeat('5',64),'16200000-0000-0000-0000-000000000014');
 IF address_limited.code<>'rate_limited' OR address_limited.retry_after IS NULL OR org_limited.code<>'rate_limited' OR org_limited.retry_after IS NULL THEN RAISE EXCEPTION 'address or organisation send limit failed'; END IF;
END $rate_limits$;

SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000003',true);
DO $associate$ DECLARE denied record; BEGIN
 SELECT * INTO denied FROM public.create_organisation_invite('blocked@invite.test','viewer',repeat('1',64),'16200000-0000-0000-0000-000000000007');
 IF denied.code<>'not_allowed' OR EXISTS(SELECT 1 FROM public.get_organisation_invites()) THEN RAISE EXCEPTION 'Associate recovered invitation administration'; END IF;
END $associate$;
SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000004',true);
DO $viewer$ DECLARE denied record; BEGIN
 SELECT * INTO denied FROM public.create_organisation_invite('blocked2@invite.test','viewer',repeat('2',64),'16200000-0000-0000-0000-000000000008');
 IF denied.code<>'not_allowed' OR EXISTS(SELECT 1 FROM public.get_organisation_invites('all')) THEN RAISE EXCEPTION 'Viewer recovered invitation administration'; END IF;
END $viewer$;
SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000007',true);
DO $suspended$ DECLARE denied record; BEGIN
 SELECT * INTO denied FROM public.create_organisation_invite('blocked3@invite.test','viewer',repeat('3',64),'16200000-0000-0000-0000-000000000009');
 IF denied.code<>'not_allowed' OR EXISTS(SELECT 1 FROM public.get_organisation_invites('all')) THEN RAISE EXCEPTION 'Suspended member retained invitation authority'; END IF;
END $suspended$;

SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000005',true);
DO $accept$
DECLARE invitation record; mismatch record; accepted record; replay record;
BEGIN
 SELECT * INTO invitation FROM public.get_my_pending_organisation_invites() WHERE org_name='Invitation fixture';
 SELECT * INTO mismatch FROM public.accept_organisation_invite('00000000-0000-0000-0000-000000000001',NULL,NULL,'16200000-0000-0000-0000-000000000010');
 SELECT * INTO accepted FROM public.accept_organisation_invite(invitation.id,NULL,NULL,'16200000-0000-0000-0000-000000000011');
 SELECT * INTO replay FROM public.accept_organisation_invite(invitation.id,NULL,NULL,'16200000-0000-0000-0000-000000000011');
 IF mismatch.code<>'not_available' OR accepted.code<>'accepted' OR replay.code<>'accepted' OR accepted.org_id<>replay.org_id THEN RAISE EXCEPTION 'verified explicit acceptance/replay failed'; END IF;
END $accept$;
RESET ROLE;

-- Recovery-only corruption probe: exact-one context must fail closed rather
-- than selecting the first active membership.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_at)
VALUES('16100000-0000-0000-0000-000000000002','16000000-0000-0000-0000-000000000001','admin','active',1,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','16000000-0000-0000-0000-000000000001',true);
DO $corrupt_context$
DECLARE denied record;
BEGIN
 SELECT * INTO denied FROM public.create_organisation_invite('corrupt-context@invite.test','viewer',repeat('8',64),'16200000-0000-0000-0000-000000000017');
 IF denied.code<>'not_allowed' OR EXISTS(SELECT 1 FROM public.get_organisation_invites('all')) THEN RAISE EXCEPTION 'corrupt active context selected a tenant'; END IF;
END $corrupt_context$;
RESET ROLE;

DO $audit_privacy$
BEGIN
 IF EXISTS(SELECT 1 FROM public.organisation_invites WHERE selector_hash IS NOT NULL AND selector_hash !~ '^[0-9a-f]{64}$')
    OR EXISTS(SELECT 1 FROM public.administration_events WHERE metadata::text~*'(token|email)' OR target_snapshot::text~*'(token|email)') THEN RAISE EXCEPTION 'secret or email leaked to governed history'; END IF;
 IF has_table_privilege('authenticated','public.organisation_invites','SELECT') OR has_table_privilege('service_role','public.organisation_invites','SELECT')
    OR has_table_privilege('authenticated','public.organisation_invitation_command_receipts','SELECT')
    OR has_function_privilege('service_role','public.get_organisation_invites(text)','EXECUTE') THEN RAISE EXCEPTION 'direct invitation access remains open'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.administration_events WHERE event_kind='organisation_invitation.resent.v1')
    OR NOT EXISTS(SELECT 1 FROM public.administration_events WHERE event_kind='organisation_invitation.revoked.v1') THEN RAISE EXCEPTION 'invitation administration was not audited'; END IF;
 IF EXISTS(SELECT 1 FROM public.organisation_invites WHERE normalized_email IN ('admin@invite.test','suspended@invite.test'))
    OR EXISTS(SELECT 1 FROM public.organisation_invite_deliveries AS delivery JOIN public.organisation_invites AS invite ON invite.id=delivery.invite_id WHERE invite.normalized_email IN ('admin@invite.test','suspended@invite.test')) THEN RAISE EXCEPTION 'existing recipient invitation left history or delivery effects'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organisation_invites WHERE normalized_email='admin-new@invite.test' AND lifecycle_reason='No longer required') THEN RAISE EXCEPTION 'revoke reason was not canonicalized'; END IF;
END $audit_privacy$;

ROLLBACK;
