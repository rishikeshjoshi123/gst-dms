-- Complete the date portion of 00026 for databases that applied its initial
-- version before the date-pattern correction. This is intentionally
-- idempotent: valid existing dates are never changed.
DO $$
DECLARE
  candidate record;
  parsed_doc_date date;
BEGIN
  FOR candidate IN
    SELECT id, raw_metadata->>'doc_date' AS doc_date
    FROM documents
    WHERE doc_date IS NULL
      AND raw_metadata IS NOT NULL
      AND jsonb_typeof(raw_metadata) = 'object'
      AND NULLIF(BTRIM(raw_metadata->>'doc_date'), '') IS NOT NULL
  LOOP
    parsed_doc_date := NULL;

    IF candidate.doc_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      BEGIN
        parsed_doc_date := candidate.doc_date::date;
      EXCEPTION WHEN datetime_field_overflow THEN
        parsed_doc_date := NULL;
      END;
    END IF;

    UPDATE documents
    SET doc_date = parsed_doc_date
    WHERE id = candidate.id
      AND doc_date IS NULL
      AND parsed_doc_date IS NOT NULL;
  END LOOP;
END $$;
