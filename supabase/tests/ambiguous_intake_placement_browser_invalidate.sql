\set ON_ERROR_STOP on
UPDATE public.intake_items
SET updated_at=updated_at+interval '1 second'
WHERE id='16470000-0000-0000-0000-000000000002';

DO $assert$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.review_items
    WHERE intake_id='16470000-0000-0000-0000-000000000002'
      AND status='closed' AND closure_reason='source_unavailable'
  ) THEN RAISE EXCEPTION 'Browser unavailable fixture did not close truthfully'; END IF;
END $assert$;
