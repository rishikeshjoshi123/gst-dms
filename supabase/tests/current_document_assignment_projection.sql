BEGIN;

DO $assignment_projection$
DECLARE
  definition text;
BEGIN
  SELECT pg_get_functiondef('public.read_current_document_assignment_projection(uuid,uuid[])'::regprocedure)
  INTO definition;

  IF definition !~ 'read_current_document_effective_metadata'
     OR definition ~ 'raw_metadata' THEN
    RAISE EXCEPTION 'assignment projection must consume only the current effective-metadata reader';
  END IF;

  IF definition !~ 'version\.state = ''current'''
     OR definition !~ 'version\.validation_state = ''valid'''
     OR definition !~ 'document\.deleted_at IS NULL'
     OR definition !~ 'document\.record_state = ''active''' THEN
    RAISE EXCEPTION 'assignment projection is missing a current active valid-version fence';
  END IF;
END
$assignment_projection$;

DO $assignment_surface$
BEGIN
  IF has_function_privilege('authenticated', 'public.read_current_document_assignment_projection(uuid,uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.read_current_document_assignment_projection(uuid,uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'assignment projection must remain service-only';
  END IF;
END
$assignment_surface$;

ROLLBACK;
