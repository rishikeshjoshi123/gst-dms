BEGIN;

DO $relationship_projection$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.read_current_matter_relationship_projection(uuid,uuid)'::regprocedure)
  INTO definition;
  IF definition !~ 'read_current_document_effective_metadata'
     OR definition !~ 'version\.state = ''current'''
     OR definition !~ 'version\.validation_state = ''valid'''
     OR definition !~ 'document\.record_state = ''active'''
     OR definition ~ 'raw_metadata|document\.doc_type[[:space:],)]|document\.reference_number[[:space:],)]' THEN
    RAISE EXCEPTION 'relationship projection must be current-effective only';
  END IF;
END
$relationship_projection$;

DO $relationship_surface$
BEGIN
  IF has_function_privilege('authenticated', 'public.read_current_matter_relationship_projection(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.fuzzy_match_current_matter_relationship_reference(uuid,uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.current_relationship_reference_exists_in_other_matter(uuid,uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.read_current_matter_relationship_projection(uuid,uuid)', 'EXECUTE')
     OR has_table_privilege('service_role', 'public.document_effective_metadata', 'SELECT') THEN
    RAISE EXCEPTION 'relationship projection and matchers must remain service-only';
  END IF;
END
$relationship_surface$;

ROLLBACK;
