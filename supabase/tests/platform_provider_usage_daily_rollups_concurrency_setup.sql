-- Run by platform_provider_usage_daily_rollups_concurrency.sh after a local reset.
BEGIN;

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000000', 'e7100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'usage-rollup-race@example.test', 'not-used', now(), '{}', '{}', now(), now());
INSERT INTO public.organisations (id, name, created_by)
VALUES ('e7100000-0000-0000-0000-000000000101', 'Usage rollup concurrency fixture', 'e7100000-0000-0000-0000-000000000001');
INSERT INTO public.file_assets (id, org_id, bucket_id, object_key, byte_size, availability)
VALUES ('e7100000-0000-0000-0000-000000000201', 'e7100000-0000-0000-0000-000000000101', 'documents', 'orgs/e7100000-0000-0000-0000-000000000101/assets/e7100000-0000-0000-0000-000000000201/original.pdf', 1, 'reserved');
INSERT INTO public.source_analysis_runs (id, org_id, asset_id, request_key, idempotency_key)
VALUES ('e7100000-0000-0000-0000-000000000301', 'e7100000-0000-0000-0000-000000000101', 'e7100000-0000-0000-0000-000000000201', 'usage-rollup-race', 'usage-rollup-race');

DO $setup$
DECLARE catalogue_id uuid; pricing_id uuid;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  INSERT INTO public.model_catalogue_versions (provider_key, model_key, revision, state, origin, reason_code, effective_from)
  VALUES ('fixture', 'usage-rollup-race-model', 1, 'active', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z') RETURNING id INTO catalogue_id;
  INSERT INTO public.runtime_config_versions (catalogue_version_id, provider_key, model_key, operation_family, revision, state, reason_code, effective_from)
  VALUES (catalogue_id, 'fixture', 'usage-rollup-race-model', 'fixture_usage_rollup_race', 1, 'enabled', 'fixture_verified', '2026-01-01T00:00:00Z');
  INSERT INTO public.provider_pricing_versions (catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin, reason_code, effective_from)
  VALUES (catalogue_id, 'fixture', 'usage-rollup-race-model', 1, 'input_tokens', 'priced', 'platform_verified', 'fixture_verified', '2026-01-01T00:00:00Z') RETURNING id INTO pricing_id;
  INSERT INTO public.provider_pricing_rate_items (pricing_version_id, billable_unit, unit_quantity, micro_usd_amount)
  VALUES (pricing_id, 'input_token', 1, 2);
  PERFORM set_config('casechain.platform_configuration.write', '', true);
END;
$setup$;

COMMIT;
