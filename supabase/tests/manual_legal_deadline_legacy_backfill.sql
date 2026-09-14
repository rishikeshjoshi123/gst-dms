-- The deadline acceptance runner injects these adversarial rows immediately after 00158.
\set ON_ERROR_STOP on
DO $legacy_backfill$
DECLARE item record;
BEGIN
  FOR item IN
    SELECT deadline.id,deadline.description,deadline.title,deadline.origin,deadline.verification_state,
      version.obligation,version.title version_title,version.manual_basis
    FROM public.deadlines deadline
    JOIN public.deadline_versions version ON version.deadline_id=deadline.id AND version.revision=1
    WHERE deadline.id IN (
      'e1580000-0000-0000-0000-000000000001','e1580000-0000-0000-0000-000000000002',
      'e1580000-0000-0000-0000-000000000003','e1580000-0000-0000-0000-000000000004'
    )
  LOOP
    IF item.origin<>'legacy' OR item.verification_state<>'provisional'
      OR item.description IS NULL OR char_length(item.description) NOT BETWEEN 2 AND 1000
      OR item.description<>btrim(item.description) OR item.description ~ '[[:cntrl:]]'
      OR char_length(item.title) NOT BETWEEN 2 AND 160 OR item.title<>btrim(item.title) OR item.title ~ '[[:cntrl:]]'
      OR item.obligation<>item.description OR item.version_title<>item.title
      OR item.manual_basis<>'Legacy record; verification not established.' THEN
      RAISE EXCEPTION 'invalid legacy normalization %',to_jsonb(item);
    END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM public.deadlines WHERE id='e1580000-0000-0000-0000-000000000001' AND description='Legacy deadline')
    OR NOT EXISTS(SELECT 1 FROM public.deadlines WHERE id='e1580000-0000-0000-0000-000000000002' AND description='Legacy deadline')
    OR NOT EXISTS(SELECT 1 FROM public.deadlines WHERE id='e1580000-0000-0000-0000-000000000003' AND description='Court order')
    OR NOT EXISTS(SELECT 1 FROM public.deadlines WHERE id='e1580000-0000-0000-0000-000000000004' AND char_length(description)=1000) THEN
    RAISE EXCEPTION 'legacy adversarial cases were not normalized deterministically';
  END IF;
  IF (SELECT count(*) FROM public.deadlines WHERE id::text LIKE 'e1580000-%')<>4 THEN RAISE EXCEPTION 'legacy fixture rows missing'; END IF;
END $legacy_backfill$;
SELECT 'manual legal deadline legacy backfill passed' AS result;
