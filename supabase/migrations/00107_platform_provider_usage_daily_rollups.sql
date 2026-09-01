-- Platform Operations: private UTC daily usage projection.
--
-- This is deliberately a trigger-owned consumer of the immutable provider
-- ledger. It exposes no browser/API reader and does not touch legacy
-- ai_usage_logs or the unsafe tenant /usage surface. The event trigger is
-- initially deferred because the ledger writer appends an event before its
-- immutable line items; failure at commit rolls the ledger append back too.
BEGIN;

CREATE TABLE public.provider_usage_daily_rollups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  usage_day date NOT NULL,
  operation_family text NOT NULL CHECK (operation_family ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  provider_key text NOT NULL CHECK (provider_key ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  model_key text NOT NULL CHECK (model_key ~ '^[a-z0-9][a-z0-9._:/-]{0,159}$'),
  quality public.provider_usage_quality NOT NULL,
  event_count bigint NOT NULL CHECK (event_count > 0),
  costed_event_count bigint NOT NULL CHECK (costed_event_count >= 0),
  uncosted_event_count bigint NOT NULL CHECK (uncosted_event_count >= 0),
  cost_micro_usd bigint CHECK (cost_micro_usd IS NULL OR cost_micro_usd >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_usage_daily_rollups_grain_unique UNIQUE (
    org_id, usage_day, operation_family, provider_key, model_key, quality
  ),
  CONSTRAINT provider_usage_daily_rollups_cost_shape CHECK (
    costed_event_count + uncosted_event_count = event_count
    AND (costed_event_count = 0) = (cost_micro_usd IS NULL)
    AND (quality <> 'priced'::public.provider_usage_quality
      OR (costed_event_count = event_count AND uncosted_event_count = 0 AND cost_micro_usd IS NOT NULL))
    AND (quality <> 'unpriced'::public.provider_usage_quality
      OR (costed_event_count = 0 AND uncosted_event_count = event_count AND cost_micro_usd IS NULL))
  )
);

CREATE TABLE public.provider_usage_daily_rollup_line_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_usage_daily_rollup_id uuid NOT NULL REFERENCES public.provider_usage_daily_rollups(id) ON DELETE RESTRICT,
  billable_unit public.provider_billable_unit NOT NULL,
  provider_quantity bigint NOT NULL CHECK (provider_quantity > 0),
  costed_quantity bigint NOT NULL CHECK (costed_quantity >= 0),
  uncosted_quantity bigint NOT NULL CHECK (uncosted_quantity >= 0),
  cost_micro_usd bigint CHECK (cost_micro_usd IS NULL OR cost_micro_usd >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_usage_daily_rollup_line_items_unit_unique UNIQUE (
    provider_usage_daily_rollup_id, billable_unit
  ),
  CONSTRAINT provider_usage_daily_rollup_line_items_cost_shape CHECK (
    costed_quantity + uncosted_quantity = provider_quantity
    AND (costed_quantity = 0) = (cost_micro_usd IS NULL)
  )
);

CREATE INDEX provider_usage_daily_rollups_org_day_idx
  ON public.provider_usage_daily_rollups (org_id, usage_day DESC);
CREATE INDEX provider_usage_daily_rollup_line_items_rollup_idx
  ON public.provider_usage_daily_rollup_line_items (provider_usage_daily_rollup_id);

CREATE OR REPLACE FUNCTION public.provider_usage_daily_rollups_are_trigger_owned()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF current_setting('casechain.provider_usage_rollup.write', true) IS DISTINCT FROM 'ledger_event_trigger' THEN
    RAISE EXCEPTION 'provider usage daily rollups require the ledger event trigger';
  END IF;
  IF TG_OP NOT IN ('INSERT', 'UPDATE') THEN
    RAISE EXCEPTION 'provider usage daily rollups are append-only projections';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER provider_usage_daily_rollups_prevent_direct_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_usage_daily_rollups
  FOR EACH ROW EXECUTE FUNCTION public.provider_usage_daily_rollups_are_trigger_owned();
CREATE TRIGGER provider_usage_daily_rollup_line_items_prevent_direct_mutation
  BEFORE INSERT OR UPDATE OR DELETE ON public.provider_usage_daily_rollup_line_items
  FOR EACH ROW EXECUTE FUNCTION public.provider_usage_daily_rollups_are_trigger_owned();

CREATE OR REPLACE FUNCTION public.project_provider_usage_daily_rollup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
SET TimeZone = 'UTC'
AS $$
DECLARE
  rollup_row public.provider_usage_daily_rollups%ROWTYPE;
  line_row public.provider_usage_daily_rollup_line_items%ROWTYPE;
  usage_line public.provider_usage_line_items%ROWTYPE;
  rollup_day date := (NEW.occurred_at AT TIME ZONE 'UTC')::date;
  event_is_costed boolean := NEW.cost_micro_usd IS NOT NULL;
  line_is_costed boolean;
  max_bigint constant numeric := 9223372036854775807::numeric;
BEGIN
  -- The advisory lock makes the check-then-write overflow fences serializable
  -- for every aggregate grain. Hash collisions can only add safe contention.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(
    'casechain.provider_usage.daily_rollup.' || NEW.org_id::text || ':' || rollup_day::text || ':' ||
    NEW.operation_family || ':' || NEW.provider_key || ':' || NEW.model_key || ':' || NEW.quality::text
  ));
  PERFORM set_config('casechain.provider_usage_rollup.write', 'ledger_event_trigger', true);

  SELECT * INTO rollup_row
  FROM public.provider_usage_daily_rollups
  WHERE org_id = NEW.org_id
    AND usage_day = rollup_day
    AND operation_family = NEW.operation_family
    AND provider_key = NEW.provider_key
    AND model_key = NEW.model_key
    AND quality = NEW.quality
  FOR UPDATE;

  IF rollup_row.id IS NULL THEN
    INSERT INTO public.provider_usage_daily_rollups (
      org_id, usage_day, operation_family, provider_key, model_key, quality,
      event_count, costed_event_count, uncosted_event_count, cost_micro_usd
    ) VALUES (
      NEW.org_id, rollup_day, NEW.operation_family, NEW.provider_key, NEW.model_key, NEW.quality,
      1, CASE WHEN event_is_costed THEN 1 ELSE 0 END, CASE WHEN event_is_costed THEN 0 ELSE 1 END,
      NEW.cost_micro_usd
    ) RETURNING * INTO rollup_row;
  ELSE
    IF rollup_row.event_count::numeric + 1 > max_bigint
       OR (event_is_costed AND COALESCE(rollup_row.cost_micro_usd, 0)::numeric + NEW.cost_micro_usd::numeric > max_bigint) THEN
      RAISE EXCEPTION 'provider usage daily rollup overflow';
    END IF;
    UPDATE public.provider_usage_daily_rollups
    SET event_count = rollup_row.event_count + 1,
        costed_event_count = rollup_row.costed_event_count + CASE WHEN event_is_costed THEN 1 ELSE 0 END,
        uncosted_event_count = rollup_row.uncosted_event_count + CASE WHEN event_is_costed THEN 0 ELSE 1 END,
        cost_micro_usd = CASE
          WHEN event_is_costed THEN COALESCE(rollup_row.cost_micro_usd, 0) + NEW.cost_micro_usd
          ELSE rollup_row.cost_micro_usd
        END,
        updated_at = now()
    WHERE id = rollup_row.id
    RETURNING * INTO rollup_row;
  END IF;

  FOR usage_line IN
    SELECT * FROM public.provider_usage_line_items
    WHERE provider_usage_event_id = NEW.id
    ORDER BY billable_unit
  LOOP
    line_is_costed := usage_line.cost_micro_usd IS NOT NULL;
    SELECT * INTO line_row
    FROM public.provider_usage_daily_rollup_line_items
    WHERE provider_usage_daily_rollup_id = rollup_row.id
      AND billable_unit = usage_line.billable_unit
    FOR UPDATE;

    IF line_row.id IS NULL THEN
      INSERT INTO public.provider_usage_daily_rollup_line_items (
        provider_usage_daily_rollup_id, billable_unit, provider_quantity,
        costed_quantity, uncosted_quantity, cost_micro_usd
      ) VALUES (
        rollup_row.id, usage_line.billable_unit, usage_line.provider_quantity,
        CASE WHEN line_is_costed THEN usage_line.provider_quantity ELSE 0 END,
        CASE WHEN line_is_costed THEN 0 ELSE usage_line.provider_quantity END,
        usage_line.cost_micro_usd
      );
    ELSE
      IF line_row.provider_quantity::numeric + usage_line.provider_quantity::numeric > max_bigint
         OR (line_is_costed AND COALESCE(line_row.cost_micro_usd, 0)::numeric + usage_line.cost_micro_usd::numeric > max_bigint) THEN
        RAISE EXCEPTION 'provider usage daily rollup line item overflow';
      END IF;
      UPDATE public.provider_usage_daily_rollup_line_items
      SET provider_quantity = line_row.provider_quantity + usage_line.provider_quantity,
          costed_quantity = line_row.costed_quantity + CASE WHEN line_is_costed THEN usage_line.provider_quantity ELSE 0 END,
          uncosted_quantity = line_row.uncosted_quantity + CASE WHEN line_is_costed THEN 0 ELSE usage_line.provider_quantity END,
          cost_micro_usd = CASE
            WHEN line_is_costed THEN COALESCE(line_row.cost_micro_usd, 0) + usage_line.cost_micro_usd
            ELSE line_row.cost_micro_usd
          END,
          updated_at = now()
      WHERE id = line_row.id;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

-- The ledger writer inserts an event before its line items. Deferral makes the
-- complete immutable event visible to the projector at transaction commit,
-- while retaining the same atomic outcome: a projection failure aborts both.
CREATE CONSTRAINT TRIGGER provider_usage_events_project_daily_rollup
  AFTER INSERT ON public.provider_usage_events
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.project_provider_usage_daily_rollup();

ALTER TABLE public.provider_usage_daily_rollups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_daily_rollups FORCE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_daily_rollup_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_usage_daily_rollup_line_items FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.provider_usage_daily_rollups, public.provider_usage_daily_rollup_line_items
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.provider_usage_daily_rollups_are_trigger_owned(), public.project_provider_usage_daily_rollup()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.provider_usage_daily_rollups IS
  'Private, trigger-owned UTC daily provider-usage projection. Its grain contains only opaque organisation correlation and provider accounting dimensions, never document, user, path, content, or payload data.';
COMMENT ON TABLE public.provider_usage_daily_rollup_line_items IS
  'Private, trigger-owned billable-unit quantities and cost-state totals for provider_usage_daily_rollups. Null cost means unknown/unpriced, never zero.';

COMMIT;
