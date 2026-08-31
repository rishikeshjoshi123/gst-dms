\set ON_ERROR_STOP on
BEGIN;
SELECT job_id||'|'||lease_token FROM public.claim_trash_purge_work(50,120)
WHERE operation_id=:'operation_id';
SELECT pg_advisory_lock(hashtextextended('root-operation-purge-race-ready',91));
SELECT pg_sleep(2);
SELECT pg_advisory_unlock(hashtextextended('root-operation-purge-race-ready',91));
COMMIT;
