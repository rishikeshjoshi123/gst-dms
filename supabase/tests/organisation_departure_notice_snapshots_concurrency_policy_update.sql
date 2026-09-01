BEGIN;
UPDATE public.organisation_operational_settings
SET departure_notice_days = 60
WHERE org_id = 'd3200000-0000-0000-0000-000000000001';
SELECT pg_advisory_lock(hashtextextended('departure-notice-snapshot-race-ready', 112));
SELECT pg_sleep(1);
SELECT pg_advisory_unlock(hashtextextended('departure-notice-snapshot-race-ready', 112));
COMMIT;
