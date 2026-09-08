-- Exact-current-organisation operational timezone for ordinary authenticated reads.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_current_organisation_operational_timezone()
RETURNS TABLE(org_id uuid, timezone text)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT membership.org_id
  INTO v_org
  FROM public.current_active_tenant_membership() AS membership;

  IF v_org IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT settings.org_id, settings.timezone
  FROM public.organisation_operational_settings AS settings
  WHERE settings.org_id = v_org
    AND settings.timezone = btrim(settings.timezone)
    AND settings.timezone <> ''
    AND EXISTS (
      SELECT 1
      FROM pg_catalog.pg_timezone_names AS timezone_name
      WHERE timezone_name.name = settings.timezone
    );
END $$;

REVOKE ALL ON FUNCTION public.get_current_organisation_operational_timezone() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_current_organisation_operational_timezone() TO authenticated;

COMMENT ON FUNCTION public.get_current_organisation_operational_timezone() IS
  'Returns the validated operational timezone only for the caller''s exactly one active current organisation; all other membership states fail closed.';

COMMIT;
