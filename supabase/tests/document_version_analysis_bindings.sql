-- Run after migration 00065 against a disposable local Supabase database.
-- Rollback-only: validates immutable, tenant-safe binding/materialization
-- without invoking a model or retaining legal-content provider output.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '65000000-0000-0000-0000-000000000001'; org_b uuid := '65000000-0000-0000-0000-000000000002';
  actor_a uuid := '65100000-0000-0000-0000-000000000001'; actor_b uuid := '65100000-0000-0000-0000-000000000002';
  client_a uuid := '65200000-0000-0000-0000-000000000001'; client_b uuid := '65200000-0000-0000-0000-000000000002';
  matter_a uuid := '65300000-0000-0000-0000-000000000001'; matter_b uuid := '65300000-0000-0000-0000-000000000002';
  document_a uuid := '65400000-0000-0000-0000-000000000001'; document_copy uuid := '65400000-0000-0000-0000-000000000002'; document_b uuid := '65400000-0000-0000-0000-000000000003'; document_old uuid := '65400000-0000-0000-0000-000000000004';
  asset_a uuid := '65500000-0000-0000-0000-000000000001'; asset_b uuid := '65500000-0000-0000-0000-000000000002'; asset_c uuid := '65500000-0000-0000-0000-000000000003';
  version_a uuid := '65600000-0000-0000-0000-000000000001'; version_copy uuid := '65600000-0000-0000-0000-000000000003'; version_b uuid := '65600000-0000-0000-0000-000000000004'; version_old uuid := '65600000-0000-0000-0000-000000000005'; version_old_current uuid := '65600000-0000-0000-0000-000000000006';
  run_a uuid := '65700000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated', 'version-binding-a@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', actor_b, 'authenticated', 'authenticated', 'version-binding-b@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES (org_a, 'Version binding A', actor_a), (org_b, 'Version binding B', actor_b);
  INSERT INTO public.clients(id, org_id, name) VALUES (client_a, org_a, 'A client'), (client_b, org_b, 'B client');
  INSERT INTO public.matters(id, org_id, client_id, title) VALUES (matter_a, org_a, client_a, 'A matter'), (matter_b, org_b, client_b, 'B matter');
  INSERT INTO public.documents(id, org_id, matter_id, storage_path, created_by) VALUES
    (document_a, org_a, matter_a, 'legacy/a.pdf', actor_a), (document_copy, org_a, matter_a, 'legacy/copy.pdf', actor_a), (document_b, org_b, matter_b, 'legacy/b.pdf', actor_b), (document_old, org_a, matter_a, 'legacy/old.pdf', actor_a);
  INSERT INTO public.file_assets(id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability, validated_at, validated_page_count, created_by) VALUES
    (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf', repeat('a', 64), 41, 'application/pdf', 'available', now(), 2, actor_a),
    (asset_b, org_b, 'documents', 'orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf', repeat('b', 64), 43, 'application/pdf', 'available', now(), 2, actor_b),
    (asset_c, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_c::text || '/original.pdf', repeat('c', 64), 47, 'application/pdf', 'available', now(), 2, actor_a);
  INSERT INTO public.document_versions(id, org_id, document_id, asset_id, version_number, original_filename, page_count, validation_state, state, validated_at, promoted_at, superseded_at, created_by) VALUES
    (version_a, org_a, document_a, asset_a, 1, 'a.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_a),
    (version_copy, org_a, document_copy, asset_a, 1, 'copy.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_a),
    (version_b, org_b, document_b, asset_b, 1, 'b.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_b),
    (version_old, org_a, document_old, asset_a, 1, 'old-v1.pdf', 2, 'valid', 'superseded', now(), NULL, now(), actor_a),
    (version_old_current, org_a, document_old, asset_c, 2, 'old-v2.pdf', 2, 'valid', 'current', now(), now(), NULL, actor_a);
  UPDATE public.documents SET current_version_id = version_a WHERE id = document_a;
  UPDATE public.documents SET current_version_id = version_copy WHERE id = document_copy;
  UPDATE public.documents SET current_version_id = version_b WHERE id = document_b;
  UPDATE public.documents SET current_version_id = version_old_current WHERE id = document_old;
  INSERT INTO public.source_analysis_runs(id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state, state, started_at, completed_at, lease_token, lease_expires_at, provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version) VALUES
    (run_a, org_a, asset_a, 'analysis.version-binding.a', 'analysis.version-binding.a', 'ai_extraction', 'validated', 'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24');
  PERFORM public.materialize_source_field_candidate(run_a, 'document.reference_number.a', 'document.reference_number', 'code', '"ABC/123"'::jsonb, 2, 'Reference ABC/123', NULL, 0.975, 'eligible', NULL);
END $setup$;

DO $binding_contract$
DECLARE
  org_b uuid := '65000000-0000-0000-0000-000000000002'; actor_a uuid := '65100000-0000-0000-0000-000000000001'; actor_b uuid := '65100000-0000-0000-0000-000000000002';
  document_a uuid := '65400000-0000-0000-0000-000000000001';
  version_a uuid := '65600000-0000-0000-0000-000000000001'; version_old uuid := '65600000-0000-0000-0000-000000000005'; version_copy uuid := '65600000-0000-0000-0000-000000000003'; version_b uuid := '65600000-0000-0000-0000-000000000004'; run_a uuid := '65700000-0000-0000-0000-000000000001';
  binding_a uuid; duplicate_binding uuid; old_binding uuid; copy_binding uuid; rejected boolean := false;
BEGIN
  binding_a := public.materialize_document_version_analysis(version_a, run_a, 'placement', actor_a);
  duplicate_binding := public.materialize_document_version_analysis(version_a, run_a, 'placement', actor_a);
  IF binding_a IS DISTINCT FROM duplicate_binding
     OR (SELECT count(*) FROM public.document_field_candidates WHERE document_version_analysis_binding_id = binding_a) <> 1
     OR (SELECT document_id FROM public.document_version_analysis_bindings WHERE id = binding_a) <> document_a
     OR (SELECT document_version_id FROM public.document_field_candidates WHERE document_version_analysis_binding_id = binding_a) <> version_a
     OR (SELECT page_number FROM public.document_field_candidates WHERE document_version_analysis_binding_id = binding_a) <> 2 THEN
    RAISE EXCEPTION 'document version binding did not materialize exact evidence idempotently';
  END IF;
  old_binding := public.materialize_document_version_analysis(version_old, run_a, 'placement', actor_a);
  copy_binding := public.materialize_document_version_analysis(version_copy, run_a, 'copy', actor_a);
  IF old_binding = binding_a OR copy_binding = binding_a
     OR (SELECT count(*) FROM public.document_field_candidates WHERE source_field_candidate_id = (SELECT id FROM public.source_field_candidates WHERE source_analysis_run_id = run_a)) <> 3 THEN
    RAISE EXCEPTION 'current, historical, and same-organisation copy bindings were not independently materialized';
  END IF;
  rejected := false; BEGIN PERFORM public.materialize_document_version_analysis(version_a, run_a, 'attachment', actor_a); EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'binding idempotency accepted conflicting immutable audit material'; END IF;
  rejected := false; BEGIN PERFORM public.materialize_document_version_analysis(version_a, run_a, 'placement', actor_b); EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'foreign-organisation actor was accepted for document version materialization'; END IF;
  rejected := false; BEGIN PERFORM public.materialize_document_version_analysis(version_b, run_a, 'placement', NULL); EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-organisation binding was accepted'; END IF;
  rejected := false;
  BEGIN
    INSERT INTO public.document_field_candidates(org_id, document_id, document_version_id, document_version_analysis_binding_id, source_field_candidate_id, semantic_candidate_key, field_path, value_type, normalized_value, page_number, evidence_page_count, quotation, confidence, validation_state)
    SELECT org_b, document_a, version_a, binding_a, id, semantic_candidate_key, field_path, value_type, normalized_value, page_number, evidence_page_count, quotation, confidence, validation_state FROM public.source_field_candidates WHERE source_analysis_run_id = run_a;
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant document candidate was accepted'; END IF;
  rejected := false; BEGIN UPDATE public.document_version_analysis_bindings SET created_by = NULL WHERE id = binding_a; EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'document version binding was mutable'; END IF;
  rejected := false; BEGIN UPDATE public.document_field_candidates SET confidence = 0.1 WHERE document_version_analysis_binding_id = binding_a; EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'document candidate was mutable'; END IF;
  rejected := false; BEGIN DELETE FROM public.document_field_candidates WHERE document_version_analysis_binding_id = binding_a; EXCEPTION WHEN others THEN rejected := true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'document candidate was deletable'; END IF;
END $binding_contract$;

SET LOCAL ROLE service_role;
DO $service_command_surface$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM 1 FROM public.document_version_analysis_bindings LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read bindings directly'; END IF;
  denied := false; BEGIN PERFORM 1 FROM public.document_field_candidates LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read document candidates directly'; END IF;
  PERFORM public.materialize_document_version_analysis('65600000-0000-0000-0000-000000000001', '65700000-0000-0000-0000-000000000001', 'placement', '65100000-0000-0000-0000-000000000001');
END $service_command_surface$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_is_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM public.materialize_document_version_analysis('65600000-0000-0000-0000-000000000001', '65700000-0000-0000-0000-000000000001', 'placement', NULL); EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could materialize document candidates'; END IF;
END $browser_is_denied$;
RESET ROLE;

DO $surface$
BEGIN
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.document_version_analysis_bindings'::regclass)
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.document_field_candidates'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('document_version_analysis_bindings', 'document_field_candidates'))
     OR has_table_privilege('authenticated', 'public.document_version_analysis_bindings', 'SELECT')
     OR has_table_privilege('service_role', 'public.document_field_candidates', 'SELECT')
     OR has_function_privilege('authenticated', 'public.materialize_document_version_analysis(uuid,uuid,text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.materialize_document_version_analysis(uuid,uuid,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'document provenance binding authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
