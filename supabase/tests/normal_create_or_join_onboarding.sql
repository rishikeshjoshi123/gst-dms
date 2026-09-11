\set ON_ERROR_STOP on
BEGIN;

DO $fixture$
DECLARE
  verified uuid:='14500000-0000-0000-0000-000000000001';
  unverified uuid:='14500000-0000-0000-0000-000000000002';
  joiner uuid:='14500000-0000-0000-0000-000000000003';
  suspended uuid:='14500000-0000-0000-0000-000000000004';
  foreign_user uuid:='14500000-0000-0000-0000-000000000005';
  owner_a uuid:='14500000-0000-0000-0000-000000000006';
  owner_b uuid:='14500000-0000-0000-0000-000000000007';
  org_a uuid:='14510000-0000-0000-0000-000000000001';
  org_b uuid:='14510000-0000-0000-0000-000000000002';
  created record; replay record; mismatch record; accepted record; denied record;
  owner_membership uuid; pending_count integer; pending_after boolean;
  live_invite_a uuid:='14520000-0000-0000-0000-000000000001';
  live_invite_b uuid:='14520000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(
    instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    raw_app_meta_data,raw_user_meta_data,created_at,updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000000',verified,'authenticated','authenticated','verified-create@onboarding.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',unverified,'authenticated','authenticated','unverified@onboarding.test','x',NULL,'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',joiner,'authenticated','authenticated','joiner@onboarding.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',suspended,'authenticated','authenticated','suspended@onboarding.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',foreign_user,'authenticated','authenticated','foreign@onboarding.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','owner-a@onboarding.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','owner-b@onboarding.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES
    (org_a,'Inviting organisation A',owner_a),(org_b,'Inviting organisation B',owner_b);
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(org_a,suspended,'viewer');
  UPDATE public.organisation_memberships
  SET state='suspended',suspended_at=now(),suspended_by=owner_a,suspension_reason='acceptance fixture'
  WHERE org_id=org_a AND user_id=suspended;

  INSERT INTO public.organisation_invites(
    id,org_id,normalized_email,role,state,selector_hash,invited_by_user_id,
    lifecycle_actor_id,idempotency_key,expires_at,expired_at,revoked_at
  ) VALUES
    (live_invite_a,org_a,'joiner@onboarding.test','associate','pending',repeat('a',64),owner_a,owner_a,'14530000-0000-0000-0000-000000000001',now()+interval '1 day',NULL,NULL),
    (live_invite_b,org_b,'joiner@onboarding.test','viewer','pending',repeat('b',64),owner_b,owner_b,'14530000-0000-0000-0000-000000000002',now()+interval '1 day',NULL,NULL),
    ('14520000-0000-0000-0000-000000000003',org_a,'joiner@onboarding.test','viewer','expired',NULL,owner_a,owner_a,'14530000-0000-0000-0000-000000000003',now()-interval '1 second',now(),NULL),
    ('14520000-0000-0000-0000-000000000004',org_b,'joiner@onboarding.test','viewer','revoked',NULL,owner_b,owner_b,'14530000-0000-0000-0000-000000000004',now()+interval '1 day',NULL,now()),
    ('14520000-0000-0000-0000-000000000005',org_a,'foreign@onboarding.test','viewer','pending',repeat('c',64),owner_a,owner_a,'14530000-0000-0000-0000-000000000005',now()+interval '1 day',NULL,NULL);

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  SET LOCAL ROLE authenticated;

  PERFORM set_config('request.jwt.claim.sub',unverified::text,true);
  SELECT * INTO created FROM public.create_organisation(
    'Unverified organisation','14540000-0000-0000-0000-000000000001'
  );
  IF created.code<>'not_available' OR EXISTS(
    SELECT 1 FROM public.organisations WHERE created_by=unverified
  ) THEN RAISE EXCEPTION 'unverified account created an organisation'; END IF;

  PERFORM set_config('request.jwt.claim.sub',verified::text,true);
  SELECT * INTO created FROM public.create_organisation(
    '  Verified Organisation  ','14540000-0000-0000-0000-000000000002'
  );
  SELECT organisation.owner_membership_id INTO owner_membership
  FROM public.organisations organisation WHERE organisation.id=created.org_id;
  RESET ROLE;
  IF created.code<>'ok' OR created.org_id IS NULL
     OR NOT EXISTS(SELECT 1 FROM public.organisations WHERE id=created.org_id AND name='Verified Organisation' AND created_by=verified)
     OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships WHERE id=owner_membership AND org_id=created.org_id AND user_id=verified AND role='admin' AND state='active')
     OR NOT EXISTS(SELECT 1 FROM public.organisation_operational_settings WHERE org_id=created.org_id AND timezone='Asia/Kolkata' AND departure_notice_days=30)
     OR NOT EXISTS(SELECT 1 FROM public.organisation_retention_settings WHERE org_id=created.org_id AND trash_retention_days=90 AND auto_purge_enabled)
     OR NOT EXISTS(SELECT 1 FROM public.organisation_storage_policies WHERE org_id=created.org_id)
     OR NOT EXISTS(SELECT 1 FROM public.administration_events WHERE org_id=created.org_id AND event_kind='organisation_creation.completed.v1' AND actor_user_id=verified)
     OR NOT EXISTS(SELECT 1 FROM public.activity_logs WHERE org_id=created.org_id AND action='organisation.created' AND user_id=verified)
     OR NOT EXISTS(SELECT 1 FROM public.activity_events WHERE org_id=created.org_id AND event_type='organisation.created' AND actor_id=verified)
     OR NOT EXISTS(
       SELECT 1 FROM public.activity_projector_outbox_events projector
       JOIN public.activity_events event ON event.id=projector.activity_event_id
       WHERE event.org_id=created.org_id AND event.event_type='organisation.created'
     )
  THEN RAISE EXCEPTION 'verified organisation creation was incomplete'; END IF;

  SET LOCAL ROLE authenticated;
  SELECT * INTO replay FROM public.create_organisation(
    'Verified Organisation','14540000-0000-0000-0000-000000000002'
  );
  SELECT * INTO mismatch FROM public.create_organisation(
    'Different name','14540000-0000-0000-0000-000000000002'
  );
  RESET ROLE;
  IF replay.code<>'ok' OR replay.org_id<>created.org_id
     OR (SELECT count(*) FROM public.organisations WHERE created_by=verified)<>1
     OR (SELECT count(*) FROM public.organisation_memberships WHERE org_id=created.org_id AND user_id=verified)<>1
     OR (SELECT count(*) FROM public.organisation_creation_command_receipts WHERE actor_user_id=verified AND idempotency_key='14540000-0000-0000-0000-000000000002')<>1
     OR (SELECT count(*) FROM public.administration_events WHERE org_id=created.org_id AND event_kind='organisation_creation.completed.v1')<>1
     OR (SELECT count(*) FROM public.activity_logs WHERE org_id=created.org_id AND action='organisation.created')<>1
     OR (SELECT count(*) FROM public.activity_events WHERE org_id=created.org_id AND event_type='organisation.created')<>1
     OR (
       SELECT count(*) FROM public.activity_projector_outbox_events projector
       JOIN public.activity_events event ON event.id=projector.activity_event_id
       WHERE event.org_id=created.org_id AND event.event_type='organisation.created'
     )<>1
     OR mismatch.code<>'idempotency_subject_mismatch'
  THEN RAISE EXCEPTION 'organisation creation replay was not idempotent or subject-bound'; END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub',joiner::text,true);
  SELECT count(*) INTO pending_count FROM public.get_my_pending_organisation_invites();
  IF pending_count<>2
     OR NOT EXISTS(SELECT 1 FROM public.get_my_pending_organisation_invites() WHERE id=live_invite_a AND org_name='Inviting organisation A')
     OR EXISTS(SELECT 1 FROM public.get_my_pending_organisation_invites() WHERE id NOT IN (live_invite_a,live_invite_b))
  THEN RAISE EXCEPTION 'verified joiner pending invitation projection was unsafe'; END IF;
  SELECT * INTO accepted FROM public.accept_organisation_invite(
    live_invite_a,NULL,NULL,'14540000-0000-0000-0000-000000000003'
  );
  SELECT EXISTS(SELECT 1 FROM public.get_my_pending_organisation_invites()) INTO pending_after;
  SELECT * INTO denied FROM public.create_organisation(
    'Bypass organisation','14540000-0000-0000-0000-000000000004'
  );
  RESET ROLE;
  IF accepted.code<>'accepted' OR accepted.org_id<>org_a
     OR (SELECT count(*) FROM public.organisation_memberships WHERE user_id=joiner AND state IN ('active','suspended'))<>1
     OR pending_after OR denied.code<>'not_available'
  THEN RAISE EXCEPTION 'accepted member bypassed the one-organisation entry boundary'; END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub',suspended::text,true);
  SELECT EXISTS(SELECT 1 FROM public.get_my_pending_organisation_invites()) INTO pending_after;
  SELECT * INTO denied FROM public.create_organisation(
    'Suspended bypass','14540000-0000-0000-0000-000000000005'
  );
  RESET ROLE;
  IF pending_after OR denied.code<>'not_available'
  THEN RAISE EXCEPTION 'suspended member bypassed onboarding'; END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.sub',foreign_user::text,true);
  SELECT EXISTS(
    SELECT 1 FROM public.get_my_pending_organisation_invites() WHERE id=live_invite_a
  ) INTO pending_after;
  SELECT * INTO denied FROM public.accept_organisation_invite(
    live_invite_b,NULL,NULL,'14540000-0000-0000-0000-000000000006'
  );
  RESET ROLE;
  IF pending_after OR denied.code<>'not_available'
     OR NOT EXISTS(SELECT 1 FROM public.organisation_invites WHERE id=live_invite_b AND state='pending')
  THEN RAISE EXCEPTION 'foreign invitation identity disclosed or mutated'; END IF;
END $fixture$;

DO $privileges$
BEGIN
  IF has_function_privilege('anon','public.create_organisation(text,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.create_organisation(text,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.create_organisation(text,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.organisation_creation_command_receipts','SELECT')
  THEN RAISE EXCEPTION 'normal onboarding privileges are unsafe'; END IF;
END $privileges$;

ROLLBACK;
