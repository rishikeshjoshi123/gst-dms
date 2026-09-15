-- Persistent synthetic fixture, only after document_boundary_repair_setup.sql
-- in the exclusively owned disposable Review database.
\set ON_ERROR_STOP on
DO $setup$
DECLARE target_b uuid:='152d0000-0000-0000-0000-000000000002'; rev bigint; result record;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000001',true);
  SELECT revision INTO rev FROM public.matters WHERE id=target_b;
  SELECT * INTO result FROM public.activate_matter_identifier(target_b,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/555/2026','GST/555/2026','152e0000-0000-0000-0000-000000000003',
    '15200000-0000-0000-0000-000000000003',1,'GST/555/2026','[]',
    'Synthetic human verification for overlap',gen_random_uuid());
  IF result.code<>'ok' OR
    (SELECT count(*) FROM public.review_items WHERE type='placement_conflict' AND status='needs_review'
      AND document_id IN ('152e0000-0000-0000-0000-000000000001','152e0000-0000-0000-0000-000000000002'))<>2
    THEN RAISE EXCEPTION 'Synthetic single-target fixture setup failed: %',result.code; END IF;
END $setup$;
