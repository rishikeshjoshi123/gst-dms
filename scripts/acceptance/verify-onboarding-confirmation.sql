\set ON_ERROR_STOP on

DO $verify$
DECLARE
  creator uuid;
  joiner uuid;
  created_org uuid;
BEGIN
  SELECT id INTO creator FROM auth.users WHERE email='create-browser@onboarding.test';
  SELECT id INTO joiner FROM auth.users WHERE email='join-browser@onboarding.test';
  IF creator IS NULL OR joiner IS NULL
     OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=creator AND email_confirmed_at IS NOT NULL)
     OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=joiner AND email_confirmed_at IS NOT NULL)
  THEN RAISE EXCEPTION 'confirmation-required browser accounts were not verified'; END IF;

  SELECT organisation.id INTO created_org
  FROM public.organisations organisation
  WHERE organisation.created_by=creator AND organisation.name='Browser-created organisation';
  IF created_org IS NULL
     OR NOT EXISTS(
       SELECT 1 FROM public.organisations organisation
       JOIN public.organisation_memberships membership
         ON membership.id=organisation.owner_membership_id
       WHERE organisation.id=created_org AND membership.user_id=creator
         AND membership.role='admin' AND membership.state='active'
     )
     OR NOT EXISTS(SELECT 1 FROM public.organisation_operational_settings WHERE org_id=created_org)
     OR NOT EXISTS(SELECT 1 FROM public.organisation_retention_settings WHERE org_id=created_org)
     OR NOT EXISTS(SELECT 1 FROM public.organisation_storage_policies WHERE org_id=created_org)
     OR NOT EXISTS(SELECT 1 FROM public.administration_events WHERE org_id=created_org AND event_kind='organisation_creation.completed.v1')
     OR NOT EXISTS(SELECT 1 FROM public.activity_events WHERE org_id=created_org AND event_type='organisation.created')
     OR NOT EXISTS(
       SELECT 1 FROM public.activity_projector_outbox_events projector
       JOIN public.activity_events event ON event.id=projector.activity_event_id
       WHERE event.org_id=created_org AND event.event_type='organisation.created'
     )
  THEN RAISE EXCEPTION 'browser-created organisation is incomplete'; END IF;

  IF NOT EXISTS(
       SELECT 1 FROM public.organisation_memberships
       WHERE user_id=joiner AND org_id='14610000-0000-0000-0000-000000000001'
         AND role='associate' AND state='active'
     ) OR NOT EXISTS(
       SELECT 1 FROM public.organisation_invites
       WHERE id='14620000-0000-0000-0000-000000000001' AND state='accepted'
     ) OR NOT EXISTS(
       SELECT 1 FROM public.organisation_invites
       WHERE id='14620000-0000-0000-0000-000000000002' AND state='pending'
     )
  THEN RAISE EXCEPTION 'explicit invitation acceptance did not preserve the competing invite'; END IF;
END $verify$;
