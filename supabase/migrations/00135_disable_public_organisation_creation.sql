-- The controlled pilot is invite-bound. Keep the broader creation command for
-- a later release, but remove every browser/service execution grant now.

REVOKE ALL ON FUNCTION public.create_organisation(text,uuid)
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.create_organisation(text,uuid) IS
  'Dormant organisation creation command. No application role may execute it during the invite-bound pilot.';
