-- Platform Operations prerequisite: private append-only provider-usage ledger.
-- This deliberately creates only the trusted-worker accounting boundary. It
-- does not adopt legacy ai_usage_logs/model_pricing writers or readers, add a
-- browser grant, create rollups, or backfill live or legacy usage rows.
BEGIN;

CREATE TYPE public.provider_usage_quality AS ENUM (
  'priced',
  'unpriced',
  'legacy_unverified'
);

-- A ledger entry may name only a durable operational run. This avoids putting
-- document references, provider payloads, storage locators, or user identity
-- into the platform trust domain. Additional run families require an explicit
-- future migration with its own organisation-scoped integrity proof.
CREATE TYPE public.provider_usage_subject_type AS ENUM (
  'source_analysis_run',
  'document_processing_run'
);

CREATE TABLE public.provider_usage_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  subject_type public.provider_usage_subject_type NOT NULL,
  subject_id uuid NOT NULL,
  operation_family text NOT NULL CHECK (operation_family ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  model_key text NOT NULL CHECK (model_key ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  catalogue_version_id uuid,
  runtime_config_version_id uuid,
  pricing_version_id uuid REFERENCES public.provider_pricing_versions(id) ON DELETE RESTRICT,
  quality public.provider_usage_quality NOT NULL,
  occurred_at timestamptz NOT NULL,
  correlation_id uuid NOT NULL,
  idempotency_key uuid NOT NULL UNIQUE,
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  cost_micro_usd bigint CHECK (cost_micro_usd IS NULL OR cost_micro_usd >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_usage_events_catalogue_version_fkey
    FOREIGN KEY (catalogue_version_id) REFERENCES public.model_catalogue_versions(id) ON DELETE RESTRICT,
  CONSTRAINT provider_usage_events_runtime_config_version_fkey
    FOREIGN KEY (runtime_config_version_id) REFERENCES public.runtime_config_versions(id) ON DELETE RESTRICT,
  CONSTRAINT provider_usage_events_quality_shape CHECK (
    (quality = 'priced'::public.provider_usage_quality
      AND catalogue_version_id IS NOT NULL AND runtime_config_version_id IS NOT NULL
      AND pricing_version_id IS NOT NULL AND cost_micro_usd IS NOT NULL)
    OR (quality = 'unpriced'::public.provider_usage_quality
      AND catalogue_version_id IS NOT NULL AND runtime_config_version_id IS NOT NULL
      AND pricing_version_id IS NULL AND cost_micro_usd IS NULL)
    OR (quality = 'legacy_unverified'::public.provider_usage_quality)
  )
);

-- A rate set is assembled before it is finalized. Once finalized it is the
-- immutable snapshot a resolver or ledger event may use; corrections require
-- a new effective-dated pricing version rather than a mutable rate history.
CREATE TABLE public.provider_pricing_rate_finalizations (
  pricing_version_id uuid PRIMARY KEY REFERENCES public.provider_pricing_versions(id) ON DELETE RESTRICT,
  finalized_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.provider_usage_line_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_usage_event_id uuid NOT NULL REFERENCES public.provider_usage_events(id) ON DELETE RESTRICT,
  billable_unit public.provider_billable_unit NOT NULL,
  provider_quantity bigint NOT NULL CHECK (provider_quantity > 0),
  pricing_rate_item_id uuid REFERENCES public.provider_pricing_rate_items(id) ON DELETE RESTRICT,
  cost_micro_usd bigint CHECK (cost_micro_usd IS NULL OR cost_micro_usd >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_usage_line_items_event_unit_unique UNIQUE (provider_usage_event_id, billable_unit),
  CONSTRAINT provider_usage_line_items_pricing_shape CHECK (
    (pricing_rate_item_id IS NULL AND cost_micro_usd IS NULL)
    OR (pricing_rate_item_id IS NOT NULL AND cost_micro_usd IS NOT NULL)
  )
);

CREATE INDEX provider_usage_events_org_occurred_idx
  ON public.provider_usage_events (org_id, occurred_at DESC);
CREATE INDEX provider_usage_events_quality_occurred_idx
  ON public.provider_usage_events (quality, occurred_at DESC);
CREATE INDEX provider_usage_line_items_event_idx
  ON public.provider_usage_line_items (provider_usage_event_id);

CREATE OR REPLACE FUNCTION public.provider_pricing_rate_items_match_contract(
  p_pricing_version_id uuid,
  p_pricing_contract public.provider_pricing_contract
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE p_pricing_contract
    WHEN 'input_output_tokens'::public.provider_pricing_contract THEN
      (SELECT count(*) = 2
        AND bool_and(billable_unit IN ('input_token'::public.provider_billable_unit, 'output_token'::public.provider_billable_unit))
       FROM public.provider_pricing_rate_items WHERE pricing_version_id = p_pricing_version_id)
    WHEN 'input_tokens'::public.provider_pricing_contract THEN
      (SELECT count(*) = 1
        AND bool_and(billable_unit = 'input_token'::public.provider_billable_unit)
       FROM public.provider_pricing_rate_items WHERE pricing_version_id = p_pricing_version_id)
    WHEN 'input_characters'::public.provider_pricing_contract THEN
      (SELECT count(*) = 1
        AND bool_and(billable_unit = 'character'::public.provider_billable_unit)
       FROM public.provider_pricing_rate_items WHERE pricing_version_id = p_pricing_version_id)
    ELSE false
  END
$$;

CREATE OR REPLACE FUNCTION public.provider_usage_line_items_are_valid(p_line_items jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_line_items IS NOT NULL
    AND jsonb_typeof(p_line_items) = 'array'
    AND jsonb_array_length(p_line_items) BETWEEN 1 AND 16
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_line_items) AS element
      WHERE jsonb_typeof(element) <> 'object'
        OR NOT (element ? 'unit' AND element ? 'quantity')
        OR EXISTS (
          SELECT 1 FROM jsonb_object_keys(element) AS key_name
          WHERE key_name NOT IN ('unit', 'quantity')
        )
        OR jsonb_typeof(element -> 'unit') <> 'string'
        OR element ->> 'unit' NOT IN (
          'input_token', 'output_token', 'cached_input_token', 'image', 'page', 'character', 'request'
        )
        OR jsonb_typeof(element -> 'quantity') <> 'number'
        OR element ->> 'quantity' !~ '^[1-9][0-9]{0,18}$'
        OR (element ->> 'quantity')::numeric > 9223372036854775807::numeric
    )
    AND NOT EXISTS (
      SELECT element ->> 'unit'
      FROM jsonb_array_elements(p_line_items) AS element
      GROUP BY element ->> 'unit'
      HAVING count(*) > 1
    )
$$;

CREATE OR REPLACE FUNCTION public.provider_usage_line_items_match_pricing_contract(
  p_line_items jsonb,
  p_pricing_contract public.provider_pricing_contract
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT public.provider_usage_line_items_are_valid(p_line_items)
    AND CASE p_pricing_contract
      WHEN 'input_output_tokens'::public.provider_pricing_contract THEN NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_line_items) AS element
        WHERE element ->> 'unit' NOT IN ('input_token', 'output_token')
      )
      WHEN 'input_tokens'::public.provider_pricing_contract THEN NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_line_items) AS element
        WHERE element ->> 'unit' <> 'input_token'
      )
      WHEN 'input_characters'::public.provider_pricing_contract THEN NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_line_items) AS element
        WHERE element ->> 'unit' <> 'character'
      )
      ELSE false
    END
$$;

CREATE OR REPLACE FUNCTION public.provider_usage_ledger_is_write_controlled()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'provider usage ledger is append-only';
  END IF;
  IF current_setting('casechain.provider_usage.write', true) IS DISTINCT FROM 'trusted_worker' THEN
    RAISE EXCEPTION 'provider usage ledger requires the trusted worker contract';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.provider_pricing_rate_finalizations_are_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'provider pricing rate finalizations are append-only';
  END IF;
  IF current_setting('casechain.platform_configuration.write', true) IS DISTINCT FROM 'trusted_configuration' THEN
    RAISE EXCEPTION 'provider pricing finalization requires the trusted configuration contract';
  END IF;
  RETURN NEW;
END;
$$;

-- Replaces the preliminary 00103 writer guard. Pending legacy rows may be
-- completed before finalization, but no rate item can be added after a
-- finalized pricing snapshot has become resolvable or has been used.
CREATE OR REPLACE FUNCTION public.provider_pricing_rate_items_are_write_controlled()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'provider pricing rate item history is append-only';
  END IF;
  IF current_setting('casechain.platform_configuration.write', true) NOT IN ('legacy_backfill', 'trusted_configuration') THEN
    RAISE EXCEPTION 'provider pricing rate items require the trusted configuration contract';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_finalizations AS finalized
    WHERE finalized.pricing_version_id = NEW.pricing_version_id
  ) THEN
    RAISE EXCEPTION 'provider pricing rate snapshot is finalized';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER provider_pricing_rate_items_prevent_mutation ON public.provider_pricing_rate_items;
CREATE TRIGGER provider_pricing_rate_items_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_pricing_rate_items
  FOR EACH ROW EXECUTE FUNCTION public.provider_pricing_rate_items_are_write_controlled();

CREATE TRIGGER provider_pricing_rate_finalizations_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_pricing_rate_finalizations
  FOR EACH ROW EXECUTE FUNCTION public.provider_pricing_rate_finalizations_are_append_only();

CREATE OR REPLACE FUNCTION public.finalize_provider_pricing_version(
  p_pricing_version_id uuid
)
RETURNS TABLE(code text, pricing_version_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE pricing public.provider_pricing_versions%ROWTYPE;
BEGIN
  IF p_pricing_version_id IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid;
    RETURN;
  END IF;
  SELECT * INTO pricing FROM public.provider_pricing_versions WHERE id = p_pricing_version_id;
  IF pricing.id IS NULL THEN
    RETURN QUERY SELECT 'invalid_pricing_version'::text, NULL::uuid;
    RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.provider_pricing.finalize.' || pricing.id::text));
  IF EXISTS (
    SELECT 1 FROM public.provider_pricing_rate_finalizations AS finalized
    WHERE finalized.pricing_version_id = pricing.id
  ) THEN
    RETURN QUERY SELECT 'already_finalized'::text, pricing.id;
    RETURN;
  END IF;
  IF NOT public.provider_pricing_rate_items_match_contract(pricing.id, pricing.pricing_contract) THEN
    RETURN QUERY SELECT 'invalid_rate_contract'::text, pricing.id;
    RETURN;
  END IF;
  PERFORM set_config('casechain.platform_configuration.write', 'trusted_configuration', true);
  INSERT INTO public.provider_pricing_rate_finalizations (pricing_version_id) VALUES (pricing.id);
  RETURN QUERY SELECT 'finalized'::text, pricing.id;
END;
$$;

-- A resolver never exposes a mutable rate collection as priced. It can only
-- return an exact, finalized contract; pending and incomplete versions remain
-- explicitly unpriced.
CREATE OR REPLACE FUNCTION public.resolve_verified_provider_pricing_version(
  p_provider_key text,
  p_model_key text,
  p_occurred_at timestamptz
)
RETURNS TABLE(code text, pricing_version_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
  WITH matches AS (
    SELECT pricing.id
    FROM public.provider_pricing_versions AS pricing
    JOIN public.provider_pricing_rate_finalizations AS finalized ON finalized.pricing_version_id = pricing.id
    WHERE pricing.provider_key = p_provider_key
      AND pricing.model_key = p_model_key
      AND pricing.pricing_state = 'priced'::public.provider_pricing_state
      AND pricing.effective_window @> p_occurred_at
      AND public.provider_pricing_rate_items_match_contract(pricing.id, pricing.pricing_contract)
  ), result AS (
    SELECT count(*)::integer AS match_count, (array_agg(id))[1] AS id FROM matches
  )
  SELECT
    CASE
      WHEN p_provider_key IS NULL OR p_model_key IS NULL OR p_occurred_at IS NULL THEN 'unpriced'::text
      WHEN result.match_count = 1 THEN 'priced'::text
      ELSE 'unpriced'::text
    END,
    CASE WHEN result.match_count = 1 THEN result.id ELSE NULL::uuid END
  FROM result
$$;

CREATE TRIGGER provider_usage_events_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_usage_events
  FOR EACH ROW EXECUTE FUNCTION public.provider_usage_ledger_is_write_controlled();
CREATE TRIGGER provider_usage_line_items_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_usage_line_items
  FOR EACH ROW EXECUTE FUNCTION public.provider_usage_ledger_is_write_controlled();

CREATE OR REPLACE FUNCTION public.record_provider_usage_event(
  p_org_id uuid,
  p_subject_type public.provider_usage_subject_type,
  p_subject_id uuid,
  p_operation_family text,
  p_provider_key text,
  p_model_key text,
  p_runtime_config_version_id uuid,
  p_occurred_at timestamptz,
  p_line_items jsonb,
  p_correlation_id uuid,
  p_idempotency_key uuid
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
  canonical_line_items jsonb;
  request_fingerprint text;
  existing_event public.provider_usage_events%ROWTYPE;
  runtime_config public.runtime_config_versions%ROWTYPE;
  catalogue public.model_catalogue_versions%ROWTYPE;
  candidate_pricing_id uuid;
  candidate_pricing_count integer;
  candidate_pricing_contract public.provider_pricing_contract;
  finalization_result record;
  resolved_pricing_id uuid;
  resolved_pricing_count integer;
  usage_item record;
  rate_item public.provider_pricing_rate_items%ROWTYPE;
  line_cost numeric;
  total_cost numeric := 0;
  inserted_event public.provider_usage_events%ROWTYPE;
  alert_result record;
BEGIN
  IF p_org_id IS NULL OR p_subject_type IS NULL OR p_subject_id IS NULL
     OR p_operation_family IS NULL OR p_operation_family !~ '^[a-z0-9][a-z0-9._-]{0,79}$'
     OR p_provider_key IS NULL OR p_provider_key !~ '^[a-z0-9][a-z0-9._-]{0,79}$'
     OR p_model_key IS NULL OR p_model_key !~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'
     OR p_runtime_config_version_id IS NULL OR p_occurred_at IS NULL
     OR p_correlation_id IS NULL OR p_idempotency_key IS NULL
     OR NOT public.provider_usage_line_items_are_valid(p_line_items) THEN
    RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object('unit', element ->> 'unit', 'quantity', (element ->> 'quantity')::bigint)
    ORDER BY element ->> 'unit'
  ) INTO canonical_line_items
  FROM jsonb_array_elements(p_line_items) AS element;

  request_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'org_id', p_org_id,
    'subject_type', p_subject_type::text,
    'subject_id', p_subject_id,
    'operation_family', p_operation_family,
    'provider_key', p_provider_key,
    'model_key', p_model_key,
    'runtime_config_version_id', p_runtime_config_version_id,
    'occurred_at', to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'line_items', canonical_line_items,
    'correlation_id', p_correlation_id
  )::text, 'utf8'), 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.provider_usage.idempotency.' || p_idempotency_key::text));
  SELECT * INTO existing_event
  FROM public.provider_usage_events
  WHERE idempotency_key = p_idempotency_key;
  IF existing_event.id IS NOT NULL THEN
    IF existing_event.request_fingerprint = request_fingerprint THEN
      RETURN QUERY SELECT 'replayed'::text, existing_event.id, existing_event.quality,
        existing_event.cost_micro_usd, existing_event.pricing_version_id;
    ELSE
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    END IF;
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.organisations WHERE id = p_org_id) THEN
    RETURN QUERY SELECT 'invalid_subject'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;
  IF p_subject_type = 'source_analysis_run'::public.provider_usage_subject_type
     AND NOT EXISTS (
       SELECT 1 FROM public.source_analysis_runs
       WHERE id = p_subject_id AND org_id = p_org_id
     ) THEN
    RETURN QUERY SELECT 'invalid_subject'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  ELSIF p_subject_type = 'document_processing_run'::public.provider_usage_subject_type
     AND NOT EXISTS (
       SELECT 1 FROM public.document_processing_runs
       WHERE id = p_subject_id AND org_id = p_org_id
     ) THEN
    RETURN QUERY SELECT 'invalid_subject'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO runtime_config
  FROM public.runtime_config_versions AS runtime
  WHERE runtime.id = p_runtime_config_version_id
    AND runtime.provider_key = p_provider_key
    AND runtime.model_key = p_model_key
    AND runtime.operation_family = p_operation_family
    AND runtime.state = 'enabled'::public.platform_runtime_config_state
    AND runtime.effective_window @> p_occurred_at;
  IF runtime_config.id IS NULL THEN
    RETURN QUERY SELECT 'configuration_unavailable'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT * INTO catalogue
  FROM public.model_catalogue_versions AS model_catalogue
  WHERE model_catalogue.id = runtime_config.catalogue_version_id
    AND model_catalogue.provider_key = p_provider_key
    AND model_catalogue.model_key = p_model_key
    AND model_catalogue.state = 'active'::public.platform_model_catalogue_state
    AND model_catalogue.origin = 'platform_verified'::public.platform_configuration_origin
    AND model_catalogue.effective_window @> p_occurred_at;
  IF catalogue.id IS NULL THEN
    RETURN QUERY SELECT 'configuration_unavailable'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  SELECT count(*)::integer, (array_agg(pricing.id))[1], (array_agg(pricing.pricing_contract))[1]
  INTO candidate_pricing_count, candidate_pricing_id, candidate_pricing_contract
  FROM public.provider_pricing_versions AS pricing
  WHERE pricing.catalogue_version_id = catalogue.id
    AND pricing.provider_key = p_provider_key
    AND pricing.model_key = p_model_key
    AND pricing.pricing_state = 'priced'::public.provider_pricing_state
    AND pricing.origin = 'platform_verified'::public.platform_configuration_origin
    AND pricing.effective_window @> p_occurred_at;
  IF candidate_pricing_count = 1
     AND NOT public.provider_usage_line_items_match_pricing_contract(canonical_line_items, candidate_pricing_contract) THEN
    RETURN QUERY SELECT 'pricing_contract_mismatch'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
    RETURN;
  ELSIF candidate_pricing_count = 1 THEN
    SELECT * INTO finalization_result FROM public.finalize_provider_pricing_version(candidate_pricing_id);
  END IF;

  SELECT count(*)::integer, (array_agg(pricing.id))[1]
  INTO resolved_pricing_count, resolved_pricing_id
  FROM public.provider_pricing_versions AS pricing
  JOIN public.provider_pricing_rate_finalizations AS finalized ON finalized.pricing_version_id = pricing.id
  WHERE pricing.catalogue_version_id = catalogue.id
    AND pricing.provider_key = p_provider_key
    AND pricing.model_key = p_model_key
    AND pricing.pricing_state = 'priced'::public.provider_pricing_state
    AND pricing.origin = 'platform_verified'::public.platform_configuration_origin
    AND pricing.effective_window @> p_occurred_at
    AND public.provider_pricing_rate_items_match_contract(pricing.id, pricing.pricing_contract)
    AND public.provider_usage_line_items_match_pricing_contract(canonical_line_items, pricing.pricing_contract);

  PERFORM set_config('casechain.provider_usage.write', 'trusted_worker', true);
  IF resolved_pricing_count <> 1 THEN
    INSERT INTO public.provider_usage_events (
      org_id, subject_type, subject_id, operation_family, provider_key, model_key,
      catalogue_version_id, runtime_config_version_id, quality, occurred_at,
      correlation_id, idempotency_key, request_fingerprint
    ) VALUES (
      p_org_id, p_subject_type, p_subject_id, p_operation_family, p_provider_key, p_model_key,
      catalogue.id, runtime_config.id, 'unpriced', p_occurred_at,
      p_correlation_id, p_idempotency_key, request_fingerprint
    ) RETURNING * INTO inserted_event;
    FOR usage_item IN
      SELECT element ->> 'unit' AS unit, (element ->> 'quantity')::bigint AS quantity
      FROM jsonb_array_elements(canonical_line_items) AS element
    LOOP
      INSERT INTO public.provider_usage_line_items (provider_usage_event_id, billable_unit, provider_quantity)
      VALUES (inserted_event.id, usage_item.unit::public.provider_billable_unit, usage_item.quantity);
    END LOOP;
    SELECT * INTO alert_result FROM public.upsert_platform_alert(
      'provider_usage_unpriced', 'warning', 'organisation', p_org_id, 'provider_usage_unpriced',
      jsonb_build_object('safe_code', 'pricing_unavailable', 'observed_count', 1), p_idempotency_key,
      NULL, true, p_occurred_at, 'provider_usage.unpriced'
    );
    IF alert_result.code NOT IN ('opened', 'occurred', 'reopened', 'replayed', 'resolved_recorded') THEN
      RAISE EXCEPTION 'provider usage unpriced alert was not recorded';
    END IF;
    RETURN QUERY SELECT 'recorded_unpriced'::text, inserted_event.id, inserted_event.quality, NULL::bigint, NULL::uuid;
    RETURN;
  END IF;

  FOR usage_item IN
    SELECT element ->> 'unit' AS unit, (element ->> 'quantity')::bigint AS quantity
    FROM jsonb_array_elements(canonical_line_items) AS element
  LOOP
    SELECT * INTO rate_item
    FROM public.provider_pricing_rate_items AS rate
    WHERE rate.pricing_version_id = resolved_pricing_id
      AND rate.billable_unit::text = usage_item.unit;
    line_cost := ceil((usage_item.quantity::numeric * rate_item.micro_usd_amount::numeric) / rate_item.unit_quantity::numeric);
    IF line_cost > 9223372036854775807::numeric OR total_cost + line_cost > 9223372036854775807::numeric THEN
      RETURN QUERY SELECT 'invalid_request'::text, NULL::uuid, NULL::public.provider_usage_quality, NULL::bigint, NULL::uuid;
      RETURN;
    END IF;
    total_cost := total_cost + line_cost;
  END LOOP;

  INSERT INTO public.provider_usage_events (
    org_id, subject_type, subject_id, operation_family, provider_key, model_key,
    catalogue_version_id, runtime_config_version_id, pricing_version_id, quality,
    occurred_at, correlation_id, idempotency_key, request_fingerprint, cost_micro_usd
  ) VALUES (
    p_org_id, p_subject_type, p_subject_id, p_operation_family, p_provider_key, p_model_key,
    catalogue.id, runtime_config.id, resolved_pricing_id, 'priced',
    p_occurred_at, p_correlation_id, p_idempotency_key, request_fingerprint, total_cost::bigint
  ) RETURNING * INTO inserted_event;
  FOR usage_item IN
    SELECT element ->> 'unit' AS unit, (element ->> 'quantity')::bigint AS quantity
    FROM jsonb_array_elements(canonical_line_items) AS element
  LOOP
    SELECT * INTO rate_item
    FROM public.provider_pricing_rate_items AS rate
    WHERE rate.pricing_version_id = resolved_pricing_id
      AND rate.billable_unit::text = usage_item.unit;
    line_cost := ceil((usage_item.quantity::numeric * rate_item.micro_usd_amount::numeric) / rate_item.unit_quantity::numeric);
    INSERT INTO public.provider_usage_line_items (
      provider_usage_event_id, billable_unit, provider_quantity, pricing_rate_item_id, cost_micro_usd
    ) VALUES (
      inserted_event.id, usage_item.unit::public.provider_billable_unit, usage_item.quantity, rate_item.id, line_cost::bigint
    );
  END LOOP;
  RETURN QUERY SELECT 'recorded_priced'::text, inserted_event.id, inserted_event.quality,
    inserted_event.cost_micro_usd, inserted_event.pricing_version_id;
END;
$$;

ALTER TABLE public.provider_usage_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_line_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_rate_finalizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_rate_finalizations FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.provider_usage_events, public.provider_usage_line_items, public.provider_pricing_rate_finalizations
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.provider_pricing_rate_items_match_contract(uuid,public.provider_pricing_contract),
  public.provider_usage_line_items_match_pricing_contract(jsonb,public.provider_pricing_contract),
  public.provider_usage_line_items_are_valid(jsonb),
  public.provider_usage_ledger_is_write_controlled(),
  public.provider_pricing_rate_finalizations_are_append_only(),
  public.finalize_provider_pricing_version(uuid),
  public.record_provider_usage_event(uuid,public.provider_usage_subject_type,uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.finalize_provider_pricing_version(uuid),
  public.record_provider_usage_event(uuid,public.provider_usage_subject_type,uuid,text,text,text,uuid,timestamptz,jsonb,uuid,uuid)
TO service_role;

COMMIT;
