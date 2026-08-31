-- Platform Operations prerequisite: private, immutable model catalogue,
-- runtime, and provider-pricing versions. This migration deliberately leaves
-- model_pricing and ai_usage_logs unchanged for legacy compatibility. Its only
-- service surface is an idempotent legacy seed boundary; it creates no live
-- reader, writer, browser grant, billing integration, or usage cutover.
BEGIN;

CREATE TYPE public.platform_configuration_origin AS ENUM (
  'platform_verified',
  'legacy_seed_pending_verification'
);

CREATE TYPE public.platform_model_catalogue_state AS ENUM (
  'active',
  'retired',
  'legacy_seed_pending_verification'
);

CREATE TYPE public.platform_runtime_config_state AS ENUM ('enabled', 'paused');

CREATE TYPE public.provider_billable_unit AS ENUM (
  'input_token',
  'output_token',
  'cached_input_token',
  'image',
  'page',
  'character',
  'request'
);

CREATE TYPE public.provider_pricing_state AS ENUM (
  'priced',
  'legacy_seed_pending_verification'
);

CREATE TYPE public.provider_pricing_contract AS ENUM (
  'input_output_tokens',
  'input_tokens',
  'input_characters'
);

CREATE TABLE public.model_catalogue_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  model_key text NOT NULL CHECK (model_key ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  revision integer NOT NULL CHECK (revision > 0),
  state public.platform_model_catalogue_state NOT NULL,
  origin public.platform_configuration_origin NOT NULL,
  reason_code text NOT NULL CHECK (reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  effective_window tstzrange GENERATED ALWAYS AS (
    tstzrange(effective_from, effective_to, '[)')
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT model_catalogue_versions_effective_order CHECK (
    effective_to IS NULL OR effective_to > effective_from
  ),
  CONSTRAINT model_catalogue_versions_revision_unique UNIQUE (provider_key, model_key, revision),
  CONSTRAINT model_catalogue_versions_id_provider_model_unique UNIQUE (id, provider_key, model_key),
  CONSTRAINT model_catalogue_versions_origin_shape CHECK (
    (origin = 'legacy_seed_pending_verification'::public.platform_configuration_origin
      AND state = 'legacy_seed_pending_verification'::public.platform_model_catalogue_state)
    OR (origin = 'platform_verified'::public.platform_configuration_origin
      AND state IN ('active'::public.platform_model_catalogue_state, 'retired'::public.platform_model_catalogue_state))
  )
);

CREATE TABLE public.runtime_config_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalogue_version_id uuid NOT NULL,
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  model_key text NOT NULL CHECK (model_key ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  operation_family text NOT NULL CHECK (operation_family ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  revision integer NOT NULL CHECK (revision > 0),
  state public.platform_runtime_config_state NOT NULL,
  reason_code text NOT NULL CHECK (reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  effective_window tstzrange GENERATED ALWAYS AS (
    tstzrange(effective_from, effective_to, '[)')
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT runtime_config_versions_effective_order CHECK (
    effective_to IS NULL OR effective_to > effective_from
  ),
  CONSTRAINT runtime_config_versions_revision_unique UNIQUE (provider_key, model_key, operation_family, revision),
  CONSTRAINT runtime_config_versions_catalogue_fkey
    FOREIGN KEY (catalogue_version_id, provider_key, model_key)
    REFERENCES public.model_catalogue_versions (id, provider_key, model_key)
    ON DELETE RESTRICT
);

CREATE TABLE public.provider_pricing_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  catalogue_version_id uuid NOT NULL,
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  model_key text NOT NULL CHECK (model_key ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  revision integer NOT NULL CHECK (revision > 0),
  pricing_contract public.provider_pricing_contract NOT NULL,
  pricing_state public.provider_pricing_state NOT NULL,
  origin public.platform_configuration_origin NOT NULL,
  reason_code text NOT NULL CHECK (reason_code ~ '^[a-z0-9_.-]{1,80}$'),
  legacy_source_model_name text CHECK (legacy_source_model_name IS NULL OR legacy_source_model_name ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  effective_window tstzrange GENERATED ALWAYS AS (
    tstzrange(effective_from, effective_to, '[)')
  ) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_pricing_versions_effective_order CHECK (
    effective_to IS NULL OR effective_to > effective_from
  ),
  CONSTRAINT provider_pricing_versions_revision_unique UNIQUE (provider_key, model_key, revision),
  CONSTRAINT provider_pricing_versions_catalogue_fkey
    FOREIGN KEY (catalogue_version_id, provider_key, model_key)
    REFERENCES public.model_catalogue_versions (id, provider_key, model_key)
    ON DELETE RESTRICT,
  CONSTRAINT provider_pricing_versions_origin_shape CHECK (
    (origin = 'legacy_seed_pending_verification'::public.platform_configuration_origin
      AND pricing_state = 'legacy_seed_pending_verification'::public.provider_pricing_state
      AND legacy_source_model_name IS NOT NULL)
    OR (origin = 'platform_verified'::public.platform_configuration_origin
      AND pricing_state = 'priced'::public.provider_pricing_state
      AND legacy_source_model_name IS NULL)
  ),
  CONSTRAINT provider_pricing_versions_legacy_source_unique UNIQUE (legacy_source_model_name)
);

CREATE TABLE public.provider_pricing_rate_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pricing_version_id uuid NOT NULL REFERENCES public.provider_pricing_versions(id) ON DELETE RESTRICT,
  billable_unit public.provider_billable_unit NOT NULL,
  unit_quantity bigint NOT NULL CHECK (unit_quantity > 0),
  micro_usd_amount bigint NOT NULL CHECK (micro_usd_amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_pricing_rate_items_unit_unique UNIQUE (pricing_version_id, billable_unit)
);

CREATE INDEX model_catalogue_versions_provider_model_effective_idx
  ON public.model_catalogue_versions (provider_key, model_key, effective_from DESC);
CREATE INDEX runtime_config_versions_provider_model_operation_effective_idx
  ON public.runtime_config_versions (provider_key, model_key, operation_family, effective_from DESC);
CREATE INDEX provider_pricing_versions_provider_model_effective_idx
  ON public.provider_pricing_versions (provider_key, model_key, effective_from DESC);
CREATE INDEX provider_pricing_rate_items_pricing_version_idx
  ON public.provider_pricing_rate_items (pricing_version_id, billable_unit);

-- Exclusion constraints would require an extension dependency. These advisory
-- lock-backed triggers make the same half-open effective-window invariant
-- explicit without broadening the database extension surface.
CREATE OR REPLACE FUNCTION public.platform_configuration_windows_do_not_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  conflict_exists boolean;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION '% history is append-only', TG_TABLE_NAME;
  END IF;

  IF current_setting('casechain.platform_configuration.write', true) NOT IN ('legacy_backfill', 'trusted_configuration') THEN
    RAISE EXCEPTION 'platform configuration requires the trusted configuration contract';
  END IF;

  IF TG_RELID = 'public.model_catalogue_versions'::regclass THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.model_catalogue.' || NEW.provider_key || '.' || NEW.model_key));
    SELECT EXISTS (
      SELECT 1 FROM public.model_catalogue_versions AS existing
      WHERE existing.provider_key = NEW.provider_key
        AND existing.model_key = NEW.model_key
        AND existing.effective_window && tstzrange(NEW.effective_from, NEW.effective_to, '[)')
    ) INTO conflict_exists;
  ELSIF TG_RELID = 'public.runtime_config_versions'::regclass THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.runtime_config.' || NEW.provider_key || '.' || NEW.model_key || '.' || NEW.operation_family));
    SELECT EXISTS (
      SELECT 1 FROM public.runtime_config_versions AS existing
      WHERE existing.provider_key = NEW.provider_key
        AND existing.model_key = NEW.model_key
        AND existing.operation_family = NEW.operation_family
        AND existing.effective_window && tstzrange(NEW.effective_from, NEW.effective_to, '[)')
    ) INTO conflict_exists;
  ELSE
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('casechain.provider_pricing.' || NEW.provider_key || '.' || NEW.model_key));
    SELECT EXISTS (
      SELECT 1 FROM public.provider_pricing_versions AS existing
      WHERE existing.provider_key = NEW.provider_key
        AND existing.model_key = NEW.model_key
        AND existing.effective_window && tstzrange(NEW.effective_from, NEW.effective_to, '[)')
    ) INTO conflict_exists;
  END IF;

  IF conflict_exists THEN
    RAISE EXCEPTION 'platform configuration effective windows must not overlap';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_runtime_config_is_within_catalogue_window()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  catalogue public.model_catalogue_versions%ROWTYPE;
BEGIN
  SELECT * INTO catalogue FROM public.model_catalogue_versions WHERE id = NEW.catalogue_version_id;
  IF catalogue.id IS NULL
     OR NOT (catalogue.effective_window @> tstzrange(NEW.effective_from, NEW.effective_to, '[)')) THEN
    RAISE EXCEPTION 'runtime configuration must be contained by its catalogue effective window';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_pricing_is_within_catalogue_window()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  catalogue public.model_catalogue_versions%ROWTYPE;
BEGIN
  SELECT * INTO catalogue FROM public.model_catalogue_versions WHERE id = NEW.catalogue_version_id;
  IF catalogue.id IS NULL
     OR NOT (catalogue.effective_window @> tstzrange(NEW.effective_from, NEW.effective_to, '[)')) THEN
    RAISE EXCEPTION 'provider pricing must be contained by its catalogue effective window';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_pricing_rate_items_are_write_controlled()
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
  RETURN NEW;
END;
$$;

CREATE TRIGGER model_catalogue_versions_validate_effective_window
  BEFORE INSERT OR UPDATE OR DELETE ON public.model_catalogue_versions
  FOR EACH ROW EXECUTE FUNCTION public.platform_configuration_windows_do_not_overlap();
CREATE TRIGGER runtime_config_versions_validate_effective_window
  BEFORE INSERT OR UPDATE OR DELETE ON public.runtime_config_versions
  FOR EACH ROW EXECUTE FUNCTION public.platform_configuration_windows_do_not_overlap();
CREATE TRIGGER runtime_config_versions_validate_catalogue_window
  BEFORE INSERT ON public.runtime_config_versions
  FOR EACH ROW EXECUTE FUNCTION public.platform_runtime_config_is_within_catalogue_window();
CREATE TRIGGER provider_pricing_versions_validate_effective_window
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_pricing_versions
  FOR EACH ROW EXECUTE FUNCTION public.platform_configuration_windows_do_not_overlap();
CREATE TRIGGER provider_pricing_versions_validate_catalogue_window
  BEFORE INSERT ON public.provider_pricing_versions
  FOR EACH ROW EXECUTE FUNCTION public.platform_pricing_is_within_catalogue_window();
CREATE TRIGGER provider_pricing_rate_items_prevent_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_pricing_rate_items
  FOR EACH ROW EXECUTE FUNCTION public.platform_pricing_rate_items_are_write_controlled();

-- The resolver is deliberately private and returns no dollar amount. Later
-- trusted ledger work must resolve a single verified version before computing
-- an integer micro-USD snapshot. Missing, pending, or duplicate matches are
-- explicitly unpriced; zero is never substituted for absence.
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
    WHERE pricing.provider_key = p_provider_key
      AND pricing.model_key = p_model_key
      AND pricing.pricing_state = 'priced'::public.provider_pricing_state
      AND pricing.effective_window @> p_occurred_at
      AND CASE pricing.pricing_contract
        WHEN 'input_output_tokens'::public.provider_pricing_contract THEN
          EXISTS (SELECT 1 FROM public.provider_pricing_rate_items AS rate WHERE rate.pricing_version_id = pricing.id AND rate.billable_unit = 'input_token'::public.provider_billable_unit)
          AND EXISTS (SELECT 1 FROM public.provider_pricing_rate_items AS rate WHERE rate.pricing_version_id = pricing.id AND rate.billable_unit = 'output_token'::public.provider_billable_unit)
        WHEN 'input_tokens'::public.provider_pricing_contract THEN
          EXISTS (SELECT 1 FROM public.provider_pricing_rate_items AS rate WHERE rate.pricing_version_id = pricing.id AND rate.billable_unit = 'input_token'::public.provider_billable_unit)
        WHEN 'input_characters'::public.provider_pricing_contract THEN
          EXISTS (SELECT 1 FROM public.provider_pricing_rate_items AS rate WHERE rate.pricing_version_id = pricing.id AND rate.billable_unit = 'character'::public.provider_billable_unit)
        ELSE false
      END
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

-- A legacy price value has only the mutable current row, not the historical
-- provider-rate provenance required by the new ledger. Seed it once as an
-- immutable pending-verification record, using integers only: micro-USD per
-- 1,000,000 provider-reported tokens. Invalid legacy identifiers or values are
-- intentionally skipped and therefore remain unpriced.
CREATE OR REPLACE FUNCTION public.backfill_legacy_model_pricing()
RETURNS TABLE(code text, seeded_count integer, skipped_count integer, conflict_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  legacy_price record;
  catalogue_id uuid;
  price_id uuid;
  seeded integer := 0;
  skipped integer := 0;
  conflicts integer := 0;
  input_micro_usd bigint;
  output_micro_usd bigint;
  legacy_contract public.provider_pricing_contract;
BEGIN
  PERFORM set_config('casechain.platform_configuration.write', 'legacy_backfill', true);

  FOR legacy_price IN
    SELECT model_name, input_price_per_1m, output_price_per_1m, created_at
    FROM public.model_pricing
    ORDER BY model_name
  LOOP
    IF legacy_price.model_name !~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'
       OR legacy_price.input_price_per_1m < 0
       OR legacy_price.output_price_per_1m < 0
       OR trunc(legacy_price.input_price_per_1m * 1000000) <> legacy_price.input_price_per_1m * 1000000
       OR trunc(legacy_price.output_price_per_1m * 1000000) <> legacy_price.output_price_per_1m * 1000000
       OR legacy_price.input_price_per_1m * 1000000 > 9223372036854775807::numeric
       OR legacy_price.output_price_per_1m * 1000000 > 9223372036854775807::numeric THEN
      skipped := skipped + 1;
      CONTINUE;
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('casechain.legacy_model_pricing.' || legacy_price.model_name)
    );

    SELECT pricing.id INTO price_id
    FROM public.provider_pricing_versions AS pricing
    WHERE pricing.legacy_source_model_name = legacy_price.model_name;
    IF price_id IS NOT NULL THEN
      CONTINUE;
    END IF;

    SELECT catalogue.id INTO catalogue_id
    FROM public.model_catalogue_versions AS catalogue
    WHERE catalogue.provider_key = 'legacy'
      AND catalogue.model_key = legacy_price.model_name
      AND catalogue.revision = 1;
    IF catalogue_id IS NULL THEN
      INSERT INTO public.model_catalogue_versions (
        provider_key, model_key, revision, state, origin, reason_code, effective_from
      ) VALUES (
        'legacy', legacy_price.model_name, 1, 'legacy_seed_pending_verification',
        'legacy_seed_pending_verification', 'legacy_seed_pending_verification', legacy_price.created_at
      ) RETURNING id INTO catalogue_id;
    ELSIF NOT EXISTS (
      SELECT 1 FROM public.model_catalogue_versions AS catalogue
      WHERE catalogue.id = catalogue_id
        AND catalogue.origin = 'legacy_seed_pending_verification'::public.platform_configuration_origin
        AND catalogue.state = 'legacy_seed_pending_verification'::public.platform_model_catalogue_state
    ) THEN
      conflicts := conflicts + 1;
      CONTINUE;
    END IF;

    legacy_contract := CASE legacy_price.model_name
      WHEN 'text-embedding-004' THEN 'input_characters'::public.provider_pricing_contract
      WHEN 'gemini-embedding-001' THEN 'input_tokens'::public.provider_pricing_contract
      ELSE 'input_output_tokens'::public.provider_pricing_contract
    END;

    INSERT INTO public.provider_pricing_versions (
      catalogue_version_id, provider_key, model_key, revision, pricing_contract, pricing_state, origin,
      reason_code, legacy_source_model_name, effective_from
    ) VALUES (
      catalogue_id, 'legacy', legacy_price.model_name, 1, legacy_contract, 'legacy_seed_pending_verification',
      'legacy_seed_pending_verification', 'legacy_seed_pending_verification', legacy_price.model_name,
      legacy_price.created_at
    ) ON CONFLICT (legacy_source_model_name) DO NOTHING
    RETURNING id INTO price_id;
    IF price_id IS NULL THEN
      SELECT pricing.id INTO price_id
      FROM public.provider_pricing_versions AS pricing
      WHERE pricing.legacy_source_model_name = legacy_price.model_name;
      IF price_id IS NULL THEN
        conflicts := conflicts + 1;
        CONTINUE;
      END IF;
      CONTINUE;
    END IF;

    input_micro_usd := (legacy_price.input_price_per_1m * 1000000)::bigint;
    output_micro_usd := (legacy_price.output_price_per_1m * 1000000)::bigint;
    IF legacy_contract = 'input_characters'::public.provider_pricing_contract THEN
      INSERT INTO public.provider_pricing_rate_items (
        pricing_version_id, billable_unit, unit_quantity, micro_usd_amount
      ) VALUES (price_id, 'character', 1000000, input_micro_usd);
    ELSIF legacy_contract = 'input_tokens'::public.provider_pricing_contract THEN
      INSERT INTO public.provider_pricing_rate_items (
        pricing_version_id, billable_unit, unit_quantity, micro_usd_amount
      ) VALUES (price_id, 'input_token', 1000000, input_micro_usd);
    ELSE
      INSERT INTO public.provider_pricing_rate_items (
        pricing_version_id, billable_unit, unit_quantity, micro_usd_amount
      ) VALUES
        (price_id, 'input_token', 1000000, input_micro_usd),
        (price_id, 'output_token', 1000000, output_micro_usd);
    END IF;
    seeded := seeded + 1;
  END LOOP;

  RETURN QUERY SELECT CASE WHEN conflicts > 0 THEN 'conflict'::text ELSE 'seeded'::text END, seeded, skipped, conflicts;
END;
$$;

SELECT * FROM public.backfill_legacy_model_pricing();

ALTER TABLE public.model_catalogue_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.model_catalogue_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.runtime_config_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.runtime_config_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_rate_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_pricing_rate_items FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.model_catalogue_versions,
  public.runtime_config_versions,
  public.provider_pricing_versions,
  public.provider_pricing_rate_items
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.platform_configuration_windows_do_not_overlap(),
  public.platform_runtime_config_is_within_catalogue_window(),
  public.platform_pricing_is_within_catalogue_window(),
  public.platform_pricing_rate_items_are_write_controlled(),
  public.resolve_verified_provider_pricing_version(text, text, timestamptz),
  public.backfill_legacy_model_pricing()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.backfill_legacy_model_pricing() TO service_role;

COMMIT;
