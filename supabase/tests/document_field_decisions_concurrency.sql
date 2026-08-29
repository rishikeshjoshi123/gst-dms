-- Run after migration 00066 as the local `supabase_admin` role against a
-- disposable local Supabase database.
-- This integration fixture intentionally commits a tiny synthetic setup so a
-- second PostgreSQL session can see it. It then removes only those fixed test
-- rows under the local superuser after the lock-order assertion completes.

CREATE EXTENSION IF NOT EXISTS dblink;

DO $setup$
DECLARE
  org_a uuid := '66800000-0000-0000-0000-000000000001'; actor_a uuid := '66810000-0000-0000-0000-000000000001';
  client_a uuid := '66820000-0000-0000-0000-000000000001'; matter_a uuid := '66830000-0000-0000-0000-000000000001';
  document_a uuid := '66840000-0000-0000-0000-000000000001'; asset_a uuid := '66850000-0000-0000-0000-000000000001';
  version_a uuid := '66860000-0000-0000-0000-000000000001'; run_a uuid := '66870000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated', 'field-decision-lock@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES (org_a, 'Field decision locking', actor_a);
  INSERT INTO public.clients(id, org_id, name) VALUES (client_a, org_a, 'Lock client');
  INSERT INTO public.matters(id, org_id, client_id, title) VALUES (matter_a, org_a, client_a, 'Lock matter');
  INSERT INTO public.documents(id, org_id, matter_id, storage_path, created_by) VALUES (document_a, org_a, matter_a, 'locking/a.pdf', actor_a);
  INSERT INTO public.file_assets(id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability, validated_at, validated_page_count, created_by)
  VALUES (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf', repeat('a', 64), 41, 'application/pdf', 'available', now(), 1, actor_a);
  INSERT INTO public.document_versions(id, org_id, document_id, asset_id, version_number, original_filename, page_count, validation_state, state, validated_at, promoted_at, created_by)
  VALUES (version_a, org_a, document_a, asset_a, 1, 'locking.pdf', 1, 'valid', 'current', now(), now(), actor_a);
  UPDATE public.documents SET current_version_id = version_a WHERE id = document_a;
  INSERT INTO public.source_analysis_runs(id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state, state, started_at, completed_at, lease_token, lease_expires_at, provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version)
  VALUES (run_a, org_a, asset_a, 'analysis.field-decision.lock', 'analysis.field-decision.lock', 'ai_extraction', 'validated', 'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24');
  PERFORM public.materialize_source_field_candidate(run_a, 'document.reference_number.lock', 'document.reference_number', 'code', '"LOCK/1"'::jsonb, 1, 'Lock reference', NULL, 0.95, 'eligible', NULL);
  PERFORM public.materialize_document_version_analysis(version_a, run_a, 'placement', actor_a);
END $setup$;

DO $concurrent_lock_order$
DECLARE
  version_a uuid := '66860000-0000-0000-0000-000000000001'; actor_a uuid := '66810000-0000-0000-0000-000000000001';
  candidate_a uuid;
  started_at timestamptz;
  elapsed interval;
  remote_query text;
BEGIN
  SELECT id INTO candidate_a FROM public.document_field_candidates
  WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.lock';
  IF candidate_a IS NULL THEN RAISE EXCEPTION 'locking fixture candidate was not materialized'; END IF;

  -- This is the materialization order: version lock first, then candidate
  -- lock after a delay. A former candidate-first decision command deadlocked
  -- here; the version-first command waits and completes once this session ends.
  PERFORM dblink_connect('field_decision_lock', 'host=127.0.0.1 port=5432 dbname=postgres user=postgres password=postgres');
  remote_query := format(
    'WITH locked_version AS MATERIALIZED (SELECT id FROM public.document_versions WHERE id = %L::uuid FOR UPDATE), delayed AS MATERIALIZED (SELECT pg_sleep(0.60) FROM locked_version) SELECT 1 FROM public.document_field_candidates AS candidate CROSS JOIN delayed WHERE candidate.id = %L::uuid FOR UPDATE OF candidate',
    version_a, candidate_a
  );
  PERFORM dblink_send_query('field_decision_lock', remote_query);
  PERFORM pg_sleep(0.10);

  SET LOCAL lock_timeout = '2s';
  SET LOCAL statement_timeout = '3s';
  started_at := clock_timestamp();
  PERFORM public.record_document_field_decision(
    candidate_a, 'accepted', NULL, 'Concurrent lock ordering', actor_a, 'field-decision-lock-order'
  );
  elapsed := clock_timestamp() - started_at;
  PERFORM * FROM dblink_get_result('field_decision_lock') AS result(value text);
  PERFORM dblink_disconnect('field_decision_lock');

  IF elapsed < interval '400 milliseconds' THEN
    RAISE EXCEPTION 'decision command did not wait on the version-first materialization lock';
  END IF;
END $concurrent_lock_order$;

BEGIN;
SET LOCAL session_replication_role = replica;
DELETE FROM public.document_effective_metadata WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.document_field_decisions WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.document_field_candidates WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.document_version_analysis_bindings WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.source_field_candidates WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.source_analysis_attempts WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.source_analysis_runs WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.document_versions WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.documents WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.file_assets WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.matters WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.clients WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.org_members WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.organisation_memberships WHERE org_id = '66800000-0000-0000-0000-000000000001';
DELETE FROM public.user_profiles WHERE user_id = '66810000-0000-0000-0000-000000000001';
DELETE FROM public.organisations WHERE id = '66800000-0000-0000-0000-000000000001';
DELETE FROM auth.users WHERE id = '66810000-0000-0000-0000-000000000001';
COMMIT;

DROP EXTENSION dblink;
