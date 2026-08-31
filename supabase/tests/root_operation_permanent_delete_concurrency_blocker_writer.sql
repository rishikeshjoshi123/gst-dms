\set ON_ERROR_STOP on
BEGIN;
SELECT code FROM public.register_trash_purge_blocker(
  :'operation_id','document',:'document_id','active_export',gen_random_uuid(),true
);
SELECT pg_advisory_lock(hashtextextended('root-operation-purge-blocker-ready',91));
SELECT pg_sleep(2);
SELECT pg_advisory_unlock(hashtextextended('root-operation-purge-blocker-ready',91));
COMMIT;
