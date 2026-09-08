-- Run after migration 00135. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $grants$
BEGIN
  IF has_function_privilege('anon','public.create_organisation(text,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.create_organisation(text,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.create_organisation(text,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'pilot organisation creation grant remained available';
  END IF;
END $grants$;

SET LOCAL ROLE authenticated;
DO $direct_call$
BEGIN
  BEGIN
    PERFORM public.create_organisation('Forbidden pilot organisation',gen_random_uuid());
    RAISE EXCEPTION 'authenticated organisation creation unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $direct_call$;
RESET ROLE;

ROLLBACK;
