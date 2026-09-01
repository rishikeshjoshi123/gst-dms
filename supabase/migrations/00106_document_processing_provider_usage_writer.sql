-- Live trusted writer for provenance-bound Vertex document extraction usage.
--
-- The worker supplies only the server-issued source-analysis run ID. This
-- command derives tenant, provider, model, completed-at time, exact provider
-- token quantities, correlation and idempotency from the durable run/attempt.
-- It intentionally does not accept document content, paths, raw provider
-- responses, an organisation ID, a model identifier, or caller-provided usage.
BEGIN;

CREATE FUNCTION public.provider_usage_deterministic_uuid(
  p_namespace text,
  p_identifier uuid
)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT format(
    '%s-%s-%s-%s-%s',
    substr(encoded, 1, 8), substr(encoded, 9, 4), substr(encoded, 13, 4),
    substr(encoded, 17, 4), substr(encoded, 21, 12)
  )::uuid
  FROM (
    SELECT encode(extensions.digest(convert_to(p_namespace || ':' || p_identifier::text, 'utf8'), 'sha256'), 'hex') AS encoded
  ) AS digest_value
$$;

CREATE FUNCTION public.record_completed_document_extraction_provider_usage(
  p_source_analysis_run_id uuid
)
RETURNS TABLE(
  code text,
  provider_usage_event_id uuid,
  quality public.provider_usage_quality,
  cost_micro_usd bigint,
  pricing_version_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET TimeZone = 'UTC'
AS $$
DECLARE
  source_run public.source_analysis_runs%ROWTYPE;
  attempt_row public.source_analysis_attempts%ROWTYPE;
  runtime_row public.runtime_config_versions%ROWTYPE;
  line_items jsonb;
  correlation_id uuid;
  idempotency_key uuid;
  alert_result record;
BEGIN
  IF p_source_analysis_run_id IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  -- The run and its latest immutable attempt are the sole authority. In
  -- particular, tenant, configured model and token quantities never cross the
  -- Trigger payload boundary into the accounting command.
  SELECT * INTO source_run
  FROM public.source_analysis_runs
  WHERE id = p_source_analysis_run_id;
  IF source_run.id IS NULL
     OR source_run.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
     OR source_run.analysis_state NOT IN (
       'validated'::public.source_analysis_provenance_state,
       'review_required'::public.source_analysis_provenance_state
     )
     OR source_run.provider IS NULL
     OR source_run.model_identifier IS NULL
     OR source_run.usage_recorded_at IS NULL THEN
    RETURN QUERY SELECT 'invalid_subject'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO attempt_row
  FROM public.source_analysis_attempts
  WHERE source_analysis_run_id = source_run.id
    AND org_id = source_run.org_id
    AND attempt_number = source_run.attempt_count;
  IF attempt_row.id IS NULL
     OR attempt_row.state <> 'succeeded'::public.source_analysis_attempt_state
     OR attempt_row.provider IS DISTINCT FROM source_run.provider
     OR attempt_row.model_identifier IS DISTINCT FROM source_run.model_identifier
     OR attempt_row.input_tokens IS DISTINCT FROM source_run.input_tokens
     OR attempt_row.output_tokens IS DISTINCT FROM source_run.output_tokens
     OR attempt_row.usage_recorded_at IS DISTINCT FROM source_run.usage_recorded_at THEN
    RETURN QUERY SELECT 'invalid_subject'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT jsonb_agg(jsonb_build_object('unit', unit, 'quantity', quantity) ORDER BY unit)
  INTO line_items
  FROM (
    SELECT 'input_token'::text AS unit, source_run.input_tokens AS quantity
    WHERE source_run.input_tokens IS NOT NULL AND source_run.input_tokens > 0
    UNION ALL
    SELECT 'output_token'::text AS unit, source_run.output_tokens AS quantity
    WHERE source_run.output_tokens IS NOT NULL AND source_run.output_tokens > 0
  ) AS measured_usage;

  correlation_id := public.provider_usage_deterministic_uuid(
    'document_ai_extraction.correlation.v1', source_run.id
  );
  idempotency_key := public.provider_usage_deterministic_uuid(
    'document_ai_extraction.idempotency.v1', attempt_row.id
  );

  IF line_items IS NULL THEN
    SELECT * INTO alert_result FROM public.upsert_platform_alert(
      'provider_usage_unpriced', 'warning', 'organisation', source_run.org_id,
      'provider_usage_unpriced',
      jsonb_build_object('safe_code', 'provider_usage_not_reported', 'observed_count', 1),
      idempotency_key, NULL, true, source_run.usage_recorded_at, 'provider_usage.unpriced'
    );
    RETURN QUERY SELECT 'usage_not_reported'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO runtime_row
  FROM public.runtime_config_versions AS runtime
  WHERE runtime.provider_key = source_run.provider
    AND runtime.model_key = source_run.model_identifier
    AND runtime.operation_family = 'document_ai_extraction'
    AND runtime.state = 'enabled'::public.platform_runtime_config_state
    AND runtime.effective_window @> source_run.usage_recorded_at;
  IF runtime_row.id IS NULL THEN
    SELECT * INTO alert_result FROM public.upsert_platform_alert(
      'provider_usage_unpriced', 'warning', 'organisation', source_run.org_id,
      'provider_usage_unpriced',
      jsonb_build_object('safe_code', 'provider_usage_configuration_unavailable', 'observed_count', 1),
      idempotency_key, NULL, true, source_run.usage_recorded_at, 'provider_usage.unpriced'
    );
    RETURN QUERY SELECT 'configuration_unavailable'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT recorded.code, recorded.provider_usage_event_id, recorded.quality,
    recorded.cost_micro_usd, recorded.pricing_version_id
  FROM public.record_provider_usage_event(
    source_run.org_id,
    'source_analysis_run'::public.provider_usage_subject_type,
    source_run.id,
    'document_ai_extraction',
    source_run.provider,
    source_run.model_identifier,
    runtime_row.id,
    source_run.usage_recorded_at,
    line_items,
    correlation_id,
    idempotency_key
  ) AS recorded;
END;
$$;

REVOKE ALL ON FUNCTION public.provider_usage_deterministic_uuid(text,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_completed_document_extraction_provider_usage(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_completed_document_extraction_provider_usage(uuid)
  TO service_role;

COMMENT ON FUNCTION public.record_completed_document_extraction_provider_usage(uuid) IS
  'Service-only append-only writer for completed provenance-bound document extraction usage. It derives tenant, model, exact tokens, correlation, and idempotency from a durable source-analysis run.';

COMMIT;
