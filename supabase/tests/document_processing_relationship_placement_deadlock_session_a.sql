-- Session A for document_processing_relationship_placement_deadlock.sh.
-- The fixture has already created these IDs. It takes the same version ->
-- document prefix as provenance, then exposes a readiness advisory lock only
-- after both row locks are held.
BEGIN;
SET lock_timeout = '2s';
SET statement_timeout = '10s';
SELECT id
FROM public.document_versions
WHERE id = '78500000-0000-0000-0000-000000000002'::uuid
FOR UPDATE;
SELECT id
FROM public.documents
WHERE id = '78400000-0000-0000-0000-000000000002'::uuid
FOR UPDATE;
SELECT pg_advisory_lock(hashtextextended('placement-deadlock-harness-ready', 78));
SELECT pg_sleep(3);
COMMIT;
