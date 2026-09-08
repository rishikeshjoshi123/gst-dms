-- No browser or service client may update the logical document row directly.
-- Governed SECURITY DEFINER commands retain their owner-authorised transitions.

DROP POLICY IF EXISTS "documents_update" ON public.documents;
REVOKE UPDATE ON TABLE public.documents FROM PUBLIC, anon, authenticated, service_role;

DO $revoke_columns$
DECLARE column_name text;
BEGIN
  FOR column_name IN
    SELECT attribute.attname
    FROM pg_catalog.pg_attribute AS attribute
    WHERE attribute.attrelid='public.documents'::regclass
      AND attribute.attnum>0 AND NOT attribute.attisdropped
  LOOP
    EXECUTE pg_catalog.format(
      'REVOKE UPDATE (%I) ON public.documents FROM PUBLIC, anon, authenticated, service_role',
      column_name
    );
  END LOOP;
END $revoke_columns$;
