BEGIN;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','91100000-0000-0000-0000-000000000001',true);
SELECT code FROM public.update_organisation_trash_retention_policy(
  '91000000-0000-0000-0000-000000000001',30,1
);
SELECT pg_advisory_lock(hashtextextended('trash-retention-policy-race-ready',90));
SELECT pg_sleep(1);
SELECT pg_advisory_unlock(hashtextextended('trash-retention-policy-race-ready',90));
COMMIT;
