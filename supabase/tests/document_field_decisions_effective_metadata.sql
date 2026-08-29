-- Run after migration 00066 against a disposable local Supabase database.
-- Rollback-only: verifies immutable human decisions and the secured effective
-- metadata projection using synthetic, bounded candidate values only.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '66000000-0000-0000-0000-000000000001'; org_b uuid := '66000000-0000-0000-0000-000000000002';
  actor_a uuid := '66100000-0000-0000-0000-000000000001'; actor_b uuid := '66100000-0000-0000-0000-000000000002'; viewer_a uuid := '66100000-0000-0000-0000-000000000003'; associate_a uuid := '66100000-0000-0000-0000-000000000004';
  client_a uuid := '66200000-0000-0000-0000-000000000001'; client_b uuid := '66200000-0000-0000-0000-000000000002';
  matter_a uuid := '66300000-0000-0000-0000-000000000001'; matter_b uuid := '66300000-0000-0000-0000-000000000002';
  document_a uuid := '66400000-0000-0000-0000-000000000001'; document_b uuid := '66400000-0000-0000-0000-000000000002';
  asset_a uuid := '66500000-0000-0000-0000-000000000001'; asset_b uuid := '66500000-0000-0000-0000-000000000002';
  version_a uuid := '66600000-0000-0000-0000-000000000001'; version_b uuid := '66600000-0000-0000-0000-000000000002';
  run_a uuid := '66700000-0000-0000-0000-000000000001'; run_b uuid := '66700000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000', actor_a, 'authenticated', 'authenticated', 'field-decision-a@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', actor_b, 'authenticated', 'authenticated', 'field-decision-b@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', viewer_a, 'authenticated', 'authenticated', 'field-decision-viewer@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-000000000000', associate_a, 'authenticated', 'authenticated', 'field-decision-associate@example.test', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
  INSERT INTO public.organisations(id, name, created_by) VALUES
    (org_a, 'Field decision A', actor_a), (org_b, 'Field decision B', actor_b);
  INSERT INTO public.org_members(org_id, user_id, role) VALUES
    (org_a, viewer_a, 'viewer'), (org_a, associate_a, 'associate');
  INSERT INTO public.clients(id, org_id, name) VALUES
    (client_a, org_a, 'A client'), (client_b, org_b, 'B client');
  INSERT INTO public.matters(id, org_id, client_id, title) VALUES
    (matter_a, org_a, client_a, 'A matter'), (matter_b, org_b, client_b, 'B matter');
  INSERT INTO public.documents(id, org_id, matter_id, storage_path, created_by) VALUES
    (document_a, org_a, matter_a, 'legacy/a.pdf', actor_a),
    (document_b, org_b, matter_b, 'legacy/b.pdf', actor_b);
  INSERT INTO public.file_assets(id, org_id, bucket_id, object_key, sha256, byte_size, detected_mime_type, availability, validated_at, validated_page_count, created_by) VALUES
    (asset_a, org_a, 'documents', 'orgs/' || org_a::text || '/assets/' || asset_a::text || '/original.pdf', repeat('a', 64), 41, 'application/pdf', 'available', now(), 2, actor_a),
    (asset_b, org_b, 'documents', 'orgs/' || org_b::text || '/assets/' || asset_b::text || '/original.pdf', repeat('b', 64), 43, 'application/pdf', 'available', now(), 2, actor_b);
  INSERT INTO public.document_versions(id, org_id, document_id, asset_id, version_number, original_filename, page_count, validation_state, state, validated_at, promoted_at, created_by) VALUES
    (version_a, org_a, document_a, asset_a, 1, 'a.pdf', 2, 'valid', 'current', now(), now(), actor_a),
    (version_b, org_b, document_b, asset_b, 1, 'b.pdf', 2, 'valid', 'current', now(), now(), actor_b);
  UPDATE public.documents SET current_version_id = version_a WHERE id = document_a;
  UPDATE public.documents SET current_version_id = version_b WHERE id = document_b;
  INSERT INTO public.source_analysis_runs(id, org_id, asset_id, request_key, idempotency_key, analysis_kind, analysis_state, state, started_at, completed_at, lease_token, lease_expires_at, provider, model_identifier, model_config_version, prompt_version, schema_version, catalogue_version, normalizer_version) VALUES
    (run_a, org_a, asset_a, 'analysis.field-decision.a', 'analysis.field-decision.a', 'ai_extraction', 'validated', 'succeeded', now() - interval '2 minutes', now() - interval '1 minute', gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24'),
    (run_b, org_a, asset_a, 'analysis.field-decision.b', 'analysis.field-decision.b', 'ai_extraction', 'validated', 'succeeded', now() - interval '1 minute', now(), gen_random_uuid(), now() + interval '1 minute', 'vertex-ai', 'gemini-2.5-flash', 'model-config-2026-08-24', 'gst-extraction-2026-08-24', 'source-analysis-schema-2026-08-24', 'gst-catalogue-2026-08-24', 'normalizer-2026-08-24');
  PERFORM public.materialize_source_field_candidate(run_a, 'document.reference_number.a', 'document.reference_number', 'code', '"ABC/123"'::jsonb, 1, 'Reference ABC/123', NULL, 0.975, 'eligible', NULL);
  PERFORM public.materialize_source_field_candidate(run_a, 'document.title.a', 'document.title', 'text', '"Suggested title"'::jsonb, 1, 'Suggested title', NULL, 0.850, 'provisional', NULL);
  PERFORM public.materialize_source_field_candidate(run_a, 'document.document_date.a', 'document.document_date', 'date', '"2026-02-28"'::jsonb, 2, 'Domain-invalid source date', NULL, 0.600, 'invalid', ARRAY['domain_invalid_date']);
  PERFORM public.materialize_source_field_candidate(run_b, 'document.reference_number.a', 'document.reference_number', 'code', '"XYZ/987"'::jsonb, 1, 'Replacement reference XYZ/987', NULL, 0.980, 'eligible', NULL);
  PERFORM public.materialize_document_version_analysis(version_a, run_a, 'placement', actor_a);
  PERFORM public.materialize_document_version_analysis(version_a, run_b, 'reextract', actor_a);
END $setup$;

DO $decision_and_projection_contract$
DECLARE
  org_a uuid := '66000000-0000-0000-0000-000000000001'; org_b uuid := '66000000-0000-0000-0000-000000000002';
  actor_a uuid := '66100000-0000-0000-0000-000000000001'; actor_b uuid := '66100000-0000-0000-0000-000000000002'; viewer_a uuid := '66100000-0000-0000-0000-000000000003'; associate_a uuid := '66100000-0000-0000-0000-000000000004';
  document_a uuid := '66400000-0000-0000-0000-000000000001'; document_b uuid := '66400000-0000-0000-0000-000000000002';
  version_a uuid := '66600000-0000-0000-0000-000000000001'; version_b uuid := '66600000-0000-0000-0000-000000000002';
  reference_candidate uuid; title_candidate uuid; invalid_candidate uuid;
  accepted_decision uuid; corrected_decision uuid; duplicate_decision uuid; associate_decision uuid; corrected_invalid_decision uuid; rejected boolean := false;
BEGIN
  SELECT id INTO reference_candidate FROM public.document_field_candidates
  WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.a'
  ORDER BY materialization_sequence DESC LIMIT 1;
  SELECT id INTO title_candidate FROM public.document_field_candidates
  WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a';
  SELECT id INTO invalid_candidate FROM public.document_field_candidates
  WHERE document_version_id = version_a AND semantic_candidate_key = 'document.document_date.a';

  IF (SELECT count(*) FROM public.document_effective_metadata WHERE document_version_id = version_a) <> 1
     OR (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a) <> 'automatic'
     OR (SELECT normalized_value FROM public.document_effective_metadata WHERE document_version_id = version_a) <> '"XYZ/987"'::jsonb
     OR (SELECT winning_document_field_candidate_id FROM public.document_effective_metadata WHERE document_version_id = version_a) <> reference_candidate THEN
    RAISE EXCEPTION 'newest eligible candidate did not deterministically win automatic metadata';
  END IF;
  PERFORM public.recompute_document_effective_metadata(version_a);
  IF (SELECT count(*) FROM public.document_effective_metadata WHERE document_version_id = version_a) <> 1
     OR (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a) <> 'automatic' THEN
    RAISE EXCEPTION 'effective metadata recompute was not idempotent';
  END IF;

  associate_decision := public.record_document_field_decision(
    title_candidate, 'accepted', NULL, 'Associate verification', associate_a, 'field-decision-associate-replay'
  );
  IF associate_decision IS DISTINCT FROM public.record_document_field_decision(
    title_candidate, 'accepted', NULL, 'Associate verification', associate_a, 'field-decision-associate-replay'
  ) THEN
    RAISE EXCEPTION 'authorised decision replay was not idempotent';
  END IF;
  UPDATE public.organisation_memberships
  SET state = 'suspended', suspended_at = now(), suspended_by = actor_a, suspension_reason = 'fixture_suspended'
  WHERE org_id = org_a AND user_id = associate_a AND state = 'active';
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'accepted', NULL, 'Associate verification', associate_a, 'field-decision-associate-replay');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'suspended actor replay bypassed current authorisation'; END IF;
  UPDATE public.organisation_memberships
  SET state = 'removed', suspended_at = NULL, suspended_by = NULL, suspension_reason = NULL,
      removed_at = now(), removed_by = actor_a, removal_reason = 'fixture_removed'
  WHERE org_id = org_a AND user_id = associate_a AND state = 'suspended';
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'accepted', NULL, 'Associate verification', associate_a, 'field-decision-associate-replay');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'removed actor replay bypassed current authorisation'; END IF;

  accepted_decision := public.record_document_field_decision(
    title_candidate, 'accepted', NULL, 'Source title verified', actor_a, 'field-decision-title-accept'
  );
  IF (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a') <> 'accepted'
     OR (SELECT normalized_value FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a') <> '"Suggested title"'::jsonb
     OR (SELECT winning_document_field_decision_id FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a') <> accepted_decision THEN
    RAISE EXCEPTION 'human acceptance did not outrank provisional automatic metadata with provenance';
  END IF;

  corrected_decision := public.record_document_field_decision(
    title_candidate, 'corrected', '"Counsel-approved title"'::jsonb, 'Corrected after review', actor_a, 'field-decision-title-correct'
  );
  duplicate_decision := public.record_document_field_decision(
    title_candidate, 'corrected', '"Counsel-approved title"'::jsonb, 'Corrected after review', actor_a, 'field-decision-title-correct'
  );
  IF corrected_decision IS DISTINCT FROM duplicate_decision
     OR (SELECT count(*) FROM public.document_field_decisions WHERE document_field_candidate_id = title_candidate) <> 3
     OR (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a') <> 'corrected'
     OR (SELECT normalized_value FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.title.a') <> '"Counsel-approved title"'::jsonb THEN
    RAISE EXCEPTION 'latest corrected human decision did not win idempotently';
  END IF;

  PERFORM public.record_document_field_decision(
    reference_candidate, 'rejected', NULL, 'Not the operative reference', actor_a, 'field-decision-reference-reject'
  );
  IF (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.a') <> 'rejected'
     OR (SELECT normalized_value FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.a') IS NOT NULL THEN
    RAISE EXCEPTION 'rejected human decision silently fell back to automatic metadata';
  END IF;
  PERFORM public.record_document_field_decision(
    reference_candidate, 'cleared', NULL, 'Deliberately blank', actor_a, 'field-decision-reference-clear'
  );
  IF (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.a') <> 'cleared'
     OR (SELECT winning_document_field_candidate_id FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.reference_number.a') <> reference_candidate THEN
    RAISE EXCEPTION 'cleared decision did not retain the exact provenance winner';
  END IF;

  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(invalid_candidate, 'accepted', NULL, 'Invalid cannot be accepted', actor_a, 'field-decision-invalid-accept');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'invalid candidate was accepted as effective metadata'; END IF;
  corrected_invalid_decision := public.record_document_field_decision(
    invalid_candidate, 'corrected', '"2026-03-01"'::jsonb, 'Human-corrected invalid source', actor_a, 'field-decision-invalid-correct'
  );
  IF (SELECT resolution FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.document_date.a') <> 'corrected'
     OR (SELECT normalized_value FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.document_date.a') <> '"2026-03-01"'::jsonb
     OR (SELECT winning_document_field_decision_id FROM public.document_effective_metadata WHERE document_version_id = version_a AND semantic_candidate_key = 'document.document_date.a') <> corrected_invalid_decision THEN
    RAISE EXCEPTION 'safe human correction did not outrank an invalid source candidate';
  END IF;
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'corrected', '123'::jsonb, 'Wrong typed replacement', actor_a, 'field-decision-wrong-replacement');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'unsafe replacement value was accepted'; END IF;
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'accepted', NULL, 'Foreign actor', actor_b, 'field-decision-foreign-actor');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'foreign-tenant actor was authorised'; END IF;
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'accepted', NULL, 'Viewer actor', viewer_a, 'field-decision-viewer-actor');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'active viewer without decision capability was authorised'; END IF;
  rejected := false; BEGIN
    PERFORM public.record_document_field_decision(title_candidate, 'accepted', NULL, 'Conflicting retry', actor_a, 'field-decision-title-correct');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'idempotency key accepted different immutable decision material'; END IF;

  rejected := false; BEGIN
    INSERT INTO public.document_field_decisions(
      org_id, document_id, document_version_id, document_field_candidate_id,
      semantic_candidate_key, field_path, value_type, action, actor_user_id, idempotency_key
    ) VALUES (
      org_b, document_b, version_b, title_candidate,
      'document.title.cross_tenant', 'document.title', 'text', 'accepted', actor_b, 'field-decision-cross-tenant'
    );
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-tenant decision candidate was accepted'; END IF;
  rejected := false; BEGIN
    UPDATE public.document_field_decisions SET reason = 'mutated' WHERE id = corrected_decision;
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'document field decision was mutable'; END IF;
  rejected := false; BEGIN
    DELETE FROM public.document_field_decisions WHERE id = corrected_decision;
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'document field decision was deletable'; END IF;
END $decision_and_projection_contract$;

-- The rollback fixture cannot open a second transaction that sees its
-- uncommitted synthetic rows. Assert the actual blocking lock order directly:
-- both the decision command and its insert guard must acquire the version lock
-- before the candidate lock, matching version materialization's write path.
DO $lock_order_contract$
DECLARE
  command_definition text;
  guard_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.record_document_field_decision(uuid,public.document_field_decision_action,jsonb,text,uuid,text)'::regprocedure
  ) INTO command_definition;
  SELECT pg_get_functiondef('public.document_field_decision_insert_guard()'::regprocedure)
    INTO guard_definition;
  IF position('SELECT * INTO version_row' IN command_definition) = 0
     OR position('FOR UPDATE' IN substr(command_definition, position('SELECT * INTO version_row' IN command_definition))) = 0
     OR position('SELECT * INTO candidate_row' IN command_definition) = 0
     OR position('FOR KEY SHARE' IN substr(command_definition, position('SELECT * INTO candidate_row' IN command_definition))) = 0
     OR position('SELECT * INTO version_row' IN command_definition)
        > position('SELECT * INTO candidate_row' IN command_definition)
     OR position('FROM public.document_versions' IN guard_definition)
        > position('FROM public.document_field_candidates' IN guard_definition) THEN
    RAISE EXCEPTION 'field decision lock ordering is not version-first';
  END IF;
END $lock_order_contract$;

SET LOCAL ROLE service_role;
DO $service_command_surface$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM 1 FROM public.document_field_decisions LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read field decisions directly'; END IF;
  denied := false; BEGIN PERFORM 1 FROM public.document_effective_metadata LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role could read effective metadata directly'; END IF;
  PERFORM public.recompute_document_effective_metadata('66600000-0000-0000-0000-000000000001');
END $service_command_surface$;
RESET ROLE;

SET LOCAL ROLE authenticated;
DO $browser_is_denied$
DECLARE denied boolean := false;
BEGIN
  BEGIN PERFORM public.recompute_document_effective_metadata('66600000-0000-0000-0000-000000000001'); EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could recompute effective metadata'; END IF;
  denied := false; BEGIN PERFORM 1 FROM public.document_field_decisions LIMIT 1; EXCEPTION WHEN insufficient_privilege THEN denied := true; END;
  IF NOT denied THEN RAISE EXCEPTION 'browser role could read field decisions'; END IF;
END $browser_is_denied$;
RESET ROLE;

DO $surface$
BEGIN
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.document_field_decisions'::regclass)
     OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid = 'public.document_effective_metadata'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('document_field_decisions', 'document_effective_metadata'))
     OR has_table_privilege('authenticated', 'public.document_field_decisions', 'SELECT')
     OR has_table_privilege('service_role', 'public.document_effective_metadata', 'SELECT')
     OR has_function_privilege('authenticated', 'public.record_document_field_decision(uuid,public.document_field_decision_action,jsonb,text,uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.recompute_document_effective_metadata(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_document_field_decision(uuid,public.document_field_decision_action,jsonb,text,uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.recompute_document_effective_metadata(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'document field decision authority surface is unsafe';
  END IF;
END $surface$;

ROLLBACK;
