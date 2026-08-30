-- Session A owns the organisation-level hierarchy lock through commit.
BEGIN;
SELECT set_config('request.jwt.claim.sub','81100000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT code FROM public.trash_resource(
  'client',
  '81200000-0000-0000-0000-000000000001',
  'fixture.race.client'
);
SELECT pg_advisory_lock(hashtextextended('hierarchical-resource-trash-race-ready', 80));
SELECT pg_sleep(2);
COMMIT;
