-- Run after migration 00134. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000','c0000000-0000-0000-0000-000000000001','authenticated','authenticated','owner@signup.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by)
VALUES('c0100000-0000-0000-0000-000000000001','Signup organisation','c0000000-0000-0000-0000-000000000001');
INSERT INTO public.organisation_invites(id,org_id,normalized_email,role,state,selector_hash,invited_by_membership_id,invited_by_user_id,expires_at)
SELECT 'c0200000-0000-0000-0000-000000000001',organisation.id,'invitee@signup.test','associate','pending',repeat('a',64),membership.id,'c0000000-0000-0000-0000-000000000001',now()+interval '1 day'
FROM public.organisations AS organisation
JOIN public.organisation_memberships AS membership ON membership.id=organisation.owner_membership_id
WHERE organisation.id='c0100000-0000-0000-0000-000000000001';
INSERT INTO public.organisation_invitation_accept_intents(invite_id,nonce_hash,expires_at)
VALUES('c0200000-0000-0000-0000-000000000001',repeat('b',64),now()+interval '20 minutes');

SET LOCAL ROLE anon;
DO $matrix$
BEGIN
  IF public.validate_organisation_invitation_signup(repeat('b',64),' Invitee@Signup.Test ')<>'eligible'
     OR public.validate_organisation_invitation_signup(repeat('b',64),'other@signup.test')<>'not_available'
     OR public.validate_organisation_invitation_signup(repeat('c',64),'invitee@signup.test')<>'not_available'
     OR public.validate_organisation_invitation_signup(NULL,'invitee@signup.test')<>'not_available' THEN
    RAISE EXCEPTION 'invite-bound signup matrix failed';
  END IF;
END $matrix$;
RESET ROLE;

UPDATE public.organisation_invitation_accept_intents SET consumed_at=now()
WHERE nonce_hash=repeat('b',64);
SET LOCAL ROLE anon;
DO $consumed$
BEGIN
  IF public.validate_organisation_invitation_signup(repeat('b',64),'invitee@signup.test')<>'not_available' THEN
    RAISE EXCEPTION 'consumed signup intent remained eligible';
  END IF;
END $consumed$;
RESET ROLE;

ROLLBACK;
