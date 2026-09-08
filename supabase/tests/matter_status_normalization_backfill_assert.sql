-- POST-00141 ASSERTION: run only after the paired pre-00141 seed and migration
-- 00141 in the same disposable database. This fixture is read-only and rolls
-- back its assertion transaction.
\set ON_ERROR_STOP on
BEGIN;

DO $backfill_assertions$
DECLARE
  normalized text[];
  reported text[];
BEGIN
  SELECT array_agg(
    status::text||'='||work_state::text||'/'||current_forum::text||'/'||record_state::text
    ORDER BY id
  ) INTO normalized
  FROM public.matters
  WHERE org_id='f4110000-0000-0000-0000-000000000001';

  IF normalized IS DISTINCT FROM ARRAY[
    'active=active/adjudication/active',
    'stayed=stayed/adjudication/active',
    'disposed=disposed/adjudication/active',
    'appeal_pending=active/first_appeal/active',
    'tribunal=active/tribunal/active',
    'high_court=active/high_court/active',
    'supreme_court=active/supreme_court/active',
    'closed=closed/other/trashed'
  ] THEN RAISE EXCEPTION 'pre-00141 Matter normalization mismatch: %',normalized; END IF;

  SELECT array_agg(
    legacy_status||'='||mapped_work_state::text||'/'||mapped_current_forum::text||'/'||record_state::text||'/'||disposition
    ORDER BY matter_id
  ) INTO reported
  FROM public.matter_status_normalization_report
  WHERE org_id='f4110000-0000-0000-0000-000000000001';

  IF reported IS DISTINCT FROM ARRAY[
    'active=active/adjudication/active/mapped',
    'stayed=stayed/adjudication/active/mapped',
    'disposed=disposed/adjudication/active/mapped',
    'appeal_pending=active/first_appeal/active/mapped',
    'tribunal=active/tribunal/active/mapped',
    'high_court=active/high_court/active/mapped',
    'supreme_court=active/supreme_court/active/mapped',
    'closed=closed/other/trashed/ambiguous_closed'
  ] THEN RAISE EXCEPTION 'normalization report mismatch: %',reported; END IF;

  IF (SELECT count(*) FROM public.matter_status_normalization_report
      WHERE org_id='f4110000-0000-0000-0000-000000000001')<>8
     OR (SELECT count(*) FROM public.matter_status_normalization_report
         WHERE org_id='f4110000-0000-0000-0000-000000000001' AND disposition='mapped')<>7
     OR (SELECT count(*) FROM public.matter_status_normalization_report
         WHERE org_id='f4110000-0000-0000-0000-000000000001' AND disposition='ambiguous_closed')<>1
     OR (SELECT count(*) FROM public.matter_status_normalization_report
         WHERE org_id='f4110000-0000-0000-0000-000000000001' AND disposition='unmapped')<>0
     OR (SELECT count(*) FROM public.matter_status_normalization_report
         WHERE org_id='f4110000-0000-0000-0000-000000000001' AND record_state='trashed')<>1 THEN
    RAISE EXCEPTION 'normalization report counts or record-state audit mismatch';
  END IF;
END $backfill_assertions$;

ROLLBACK;
