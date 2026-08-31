BEGIN;
SELECT projected_count||':'||already_projected_count
FROM public.project_due_trash_retention_team_attention(100);
SELECT pg_advisory_lock(hashtextextended('trash-retention-attention-race-ready',90));
SELECT pg_sleep(1);
SELECT pg_advisory_unlock(hashtextextended('trash-retention-attention-race-ready',90));
COMMIT;
