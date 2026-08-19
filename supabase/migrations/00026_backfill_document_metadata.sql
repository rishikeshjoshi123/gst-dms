-- Earlier inbox auto-assignment created document rows from AI metadata but did
-- not copy all display fields onto the row. Timeline cards and detail panels
-- read the row columns, so repair only blank values from the already-stored
-- metadata. Existing reviewed/correct values always win.
DO $$
DECLARE
  candidate record;
  parsed_doc_date date;
BEGIN
  FOR candidate IN
    SELECT
      id,
      raw_metadata->>'reference_number' AS reference_number,
      raw_metadata->>'doc_date' AS doc_date,
      raw_metadata->>'issued_by' AS issued_by,
      raw_metadata->>'summary' AS summary
    FROM documents
    WHERE raw_metadata IS NOT NULL
      AND jsonb_typeof(raw_metadata) = 'object'
      AND (
        (NULLIF(BTRIM(reference_number), '') IS NULL AND NULLIF(BTRIM(raw_metadata->>'reference_number'), '') IS NOT NULL)
        OR (doc_date IS NULL AND NULLIF(BTRIM(raw_metadata->>'doc_date'), '') IS NOT NULL)
        OR (NULLIF(BTRIM(issued_by), '') IS NULL AND NULLIF(BTRIM(raw_metadata->>'issued_by'), '') IS NOT NULL)
        OR (NULLIF(BTRIM(summary), '') IS NULL AND NULLIF(BTRIM(raw_metadata->>'summary'), '') IS NOT NULL)
      )
  LOOP
    parsed_doc_date := NULL;

    -- AI output is expected to be YYYY-MM-DD. A malformed historical value
    -- must not abort the migration or overwrite a valid document date.
    IF candidate.doc_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      BEGIN
        parsed_doc_date := candidate.doc_date::date;
      EXCEPTION WHEN datetime_field_overflow THEN
        parsed_doc_date := NULL;
      END;
    END IF;

    UPDATE documents
    SET
      reference_number = COALESCE(NULLIF(BTRIM(reference_number), ''), NULLIF(BTRIM(candidate.reference_number), '')),
      doc_date = COALESCE(doc_date, parsed_doc_date),
      issued_by = COALESCE(NULLIF(BTRIM(issued_by), ''), NULLIF(BTRIM(candidate.issued_by), '')),
      summary = COALESCE(NULLIF(BTRIM(summary), ''), NULLIF(BTRIM(candidate.summary), ''))
    WHERE id = candidate.id;
  END LOOP;
END $$;
