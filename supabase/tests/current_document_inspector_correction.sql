BEGIN;
DO $authority$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text)'::regprocedure) INTO definition;
  IF definition !~ 'document_row.current_version_id IS DISTINCT FROM p_document_version_id'
     OR definition !~ 'winning_document_field_candidate_id=p_document_field_candidate_id'
     OR definition !~ 'FOR UPDATE'
     OR definition !~ 'record_document_field_decision'
     OR definition ~ 'raw_metadata' THEN
    RAISE EXCEPTION 'inspector correction must atomically fence the current effective candidate';
  END IF;
  IF has_function_privilege('authenticated', 'public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'inspector correction must remain service-only';
  END IF;
END $authority$;
ROLLBACK;
