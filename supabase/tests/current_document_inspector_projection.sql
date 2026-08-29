BEGIN;

DO $inspector_projection$
DECLARE
  definition text;
BEGIN
  SELECT pg_get_functiondef('public.read_current_document_inspector_projection(uuid,uuid[])'::regprocedure)
  INTO definition;

  IF definition !~ 'read_current_document_effective_metadata'
     OR definition !~ 'winning_document_field_candidate_id'
     OR definition !~ 'current_metadata\.field_path = effective\.field_path'
     OR definition ~ 'raw_metadata' THEN
    RAISE EXCEPTION 'inspector projection must use the fenced effective metadata and winning candidate only';
  END IF;
END
$inspector_projection$;

DO $inspector_surface$
BEGIN
  IF has_function_privilege('authenticated', 'public.read_current_document_inspector_projection(uuid,uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.read_current_document_inspector_projection(uuid,uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'inspector projection must remain service-only';
  END IF;
END
$inspector_surface$;

ROLLBACK;
