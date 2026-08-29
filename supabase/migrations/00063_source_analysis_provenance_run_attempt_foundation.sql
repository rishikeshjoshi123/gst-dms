-- Normalized, asset-scoped AI provenance foundation.
--
-- This is deliberately limited to run and provider-attempt provenance. It
-- preserves the existing validation-worker contract on source_analysis_runs;
-- candidate materialisation, document bindings, effective metadata, raw model
-- output retention, and processing-worker cutover follow in later migrations.
BEGIN;

CREATE TYPE public.source_analysis_kind AS ENUM ('asset_validation', 'ai_extraction');
CREATE TYPE public.source_analysis_provenance_state AS ENUM (
  'queued',
  'running',
  'validated',
  'invalid_model_output',
  'provider_failed',
  'review_required'
);
CREATE TYPE public.source_analysis_attempt_state AS ENUM (
  'queued',
  'running',
  'succeeded',
  'invalid_model_output',
  'provider_failed'
);
CREATE TYPE public.source_analysis_failure_category AS ENUM (
  'invalid_model_output',
  'transport',
  'timeout',
  'throttled',
  'provider_unavailable',
  'provider_rejected',
  'configuration',
  'unknown'
);
CREATE TYPE public.source_analysis_retry_reason AS ENUM (
  'initial',
  'transient_retry',
  'invalid_output_regeneration',
  'operator_recovery'
);

ALTER TABLE public.source_analysis_runs
  ADD COLUMN analysis_kind public.source_analysis_kind NOT NULL DEFAULT 'asset_validation',
  ADD COLUMN analysis_state public.source_analysis_provenance_state,
  ADD COLUMN idempotency_key text,
  ADD COLUMN provider text,
  ADD COLUMN model_identifier text,
  ADD COLUMN model_config_version text,
  ADD COLUMN prompt_version text,
  ADD COLUMN schema_version text,
  ADD COLUMN catalogue_version text,
  ADD COLUMN normalizer_version text,
  ADD COLUMN provider_request_id text,
  ADD COLUMN provider_operation_id text,
  ADD COLUMN safe_error_category public.source_analysis_failure_category,
  ADD COLUMN input_tokens bigint CHECK (input_tokens IS NULL OR input_tokens >= 0),
  ADD COLUMN output_tokens bigint CHECK (output_tokens IS NULL OR output_tokens >= 0),
  ADD COLUMN billable_units numeric(18, 6) CHECK (billable_units IS NULL OR billable_units >= 0),
  ADD COLUMN cost_amount numeric(18, 6) CHECK (cost_amount IS NULL OR cost_amount >= 0),
  ADD COLUMN cost_currency text,
  ADD COLUMN latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
  ADD COLUMN usage_recorded_at timestamptz,
  ADD COLUMN superseded_by_run_id uuid;

-- request_key has been the durable source-run identity since the lifecycle
-- foundation. Backfill its explicit provenance name before making it required.
UPDATE public.source_analysis_runs
SET idempotency_key = request_key
WHERE idempotency_key IS NULL;

ALTER TABLE public.source_analysis_runs
  ALTER COLUMN idempotency_key SET NOT NULL,
  ADD CONSTRAINT source_analysis_runs_org_idempotency_unique UNIQUE (org_id, idempotency_key),
  ADD CONSTRAINT source_analysis_runs_superseded_by_org_fkey
    FOREIGN KEY (org_id, superseded_by_run_id)
    REFERENCES public.source_analysis_runs(org_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT source_analysis_runs_safe_identifiers CHECK (
    (provider IS NULL OR provider ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (model_identifier IS NULL OR model_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (model_config_version IS NULL OR model_config_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (prompt_version IS NULL OR prompt_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (schema_version IS NULL OR schema_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (catalogue_version IS NULL OR catalogue_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (normalizer_version IS NULL OR normalizer_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (provider_request_id IS NULL OR provider_request_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (provider_operation_id IS NULL OR provider_operation_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (safe_error_code IS NULL OR safe_error_code ~ '^[a-z][a-z0-9_]{0,99}$')
  ),
  ADD CONSTRAINT source_analysis_runs_ai_configuration_required CHECK (
    (analysis_kind = 'asset_validation' AND analysis_state IS NULL)
    OR (
      analysis_kind = 'ai_extraction'
      AND analysis_state IS NOT NULL
      AND provider IS NOT NULL
      AND model_identifier IS NOT NULL
      AND model_config_version IS NOT NULL
      AND prompt_version IS NOT NULL
      AND schema_version IS NOT NULL
      AND catalogue_version IS NOT NULL
      AND normalizer_version IS NOT NULL
    )
  ),
  ADD CONSTRAINT source_analysis_runs_usage_currency_consistent CHECK (
    (cost_amount IS NULL AND cost_currency IS NULL)
    OR (cost_amount IS NOT NULL AND cost_currency ~ '^[A-Z]{3}$')
  ),
  ADD CONSTRAINT source_analysis_runs_usage_timestamp_consistent CHECK (
    (input_tokens IS NULL AND output_tokens IS NULL AND billable_units IS NULL
      AND cost_amount IS NULL AND latency_ms IS NULL AND usage_recorded_at IS NULL)
    OR usage_recorded_at IS NOT NULL
  ),
  ADD CONSTRAINT source_analysis_runs_ai_state_consistent CHECK (
    analysis_kind = 'asset_validation'
    OR (
      (analysis_state = 'queued' AND state = 'queued')
      OR (analysis_state = 'running' AND state = 'running')
      OR (analysis_state = 'validated' AND state = 'succeeded')
      OR (analysis_state IN ('invalid_model_output', 'provider_failed', 'review_required') AND state = 'failed')
    )
  ),
  ADD CONSTRAINT source_analysis_runs_ai_terminal_started CHECK (
    analysis_kind <> 'ai_extraction'
    OR analysis_state NOT IN ('invalid_model_output', 'provider_failed', 'review_required')
    OR started_at IS NOT NULL
  ),
  ADD CONSTRAINT source_analysis_runs_supersession_not_self CHECK (
    superseded_by_run_id IS NULL OR superseded_by_run_id <> id
  );

CREATE INDEX source_analysis_runs_asset_kind_created_idx
  ON public.source_analysis_runs (org_id, asset_id, analysis_kind, created_at DESC);
CREATE INDEX source_analysis_runs_supersession_idx
  ON public.source_analysis_runs (org_id, superseded_by_run_id)
  WHERE superseded_by_run_id IS NOT NULL;

CREATE TABLE public.source_analysis_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  source_analysis_run_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  state public.source_analysis_attempt_state NOT NULL DEFAULT 'queued',
  retry_reason public.source_analysis_retry_reason NOT NULL DEFAULT 'initial',
  provider text NOT NULL,
  model_identifier text NOT NULL,
  model_config_version text NOT NULL,
  prompt_version text NOT NULL,
  schema_version text NOT NULL,
  catalogue_version text NOT NULL,
  normalizer_version text NOT NULL,
  provider_request_id text,
  provider_operation_id text,
  provider_status_code integer CHECK (provider_status_code IS NULL OR provider_status_code BETWEEN 100 AND 599),
  safe_error_category public.source_analysis_failure_category,
  safe_error_code text,
  input_tokens bigint CHECK (input_tokens IS NULL OR input_tokens >= 0),
  output_tokens bigint CHECK (output_tokens IS NULL OR output_tokens >= 0),
  billable_units numeric(18, 6) CHECK (billable_units IS NULL OR billable_units >= 0),
  cost_amount numeric(18, 6) CHECK (cost_amount IS NULL OR cost_amount >= 0),
  cost_currency text,
  latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
  usage_recorded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  CONSTRAINT source_analysis_attempts_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT source_analysis_attempts_run_org_fkey
    FOREIGN KEY (org_id, source_analysis_run_id)
    REFERENCES public.source_analysis_runs(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT source_analysis_attempts_run_number_unique UNIQUE (source_analysis_run_id, attempt_number),
  CONSTRAINT source_analysis_attempts_safe_identifiers CHECK (
    provider ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND model_identifier ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND model_config_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND prompt_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND schema_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND catalogue_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND normalizer_version ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
    AND (provider_request_id IS NULL OR provider_request_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (provider_operation_id IS NULL OR provider_operation_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$')
    AND (safe_error_code IS NULL OR safe_error_code ~ '^[a-z][a-z0-9_]{0,99}$')
  ),
  CONSTRAINT source_analysis_attempts_usage_currency_consistent CHECK (
    (cost_amount IS NULL AND cost_currency IS NULL)
    OR (cost_amount IS NOT NULL AND cost_currency ~ '^[A-Z]{3}$')
  ),
  CONSTRAINT source_analysis_attempts_usage_timestamp_consistent CHECK (
    (input_tokens IS NULL AND output_tokens IS NULL AND billable_units IS NULL
      AND cost_amount IS NULL AND latency_ms IS NULL AND usage_recorded_at IS NULL)
    OR usage_recorded_at IS NOT NULL
  ),
  CONSTRAINT source_analysis_attempts_state_timestamps CHECK (
    (state = 'queued' AND started_at IS NULL AND completed_at IS NULL AND failed_at IS NULL)
    OR (state = 'running' AND started_at IS NOT NULL AND completed_at IS NULL AND failed_at IS NULL)
    OR (state = 'succeeded' AND started_at IS NOT NULL AND completed_at IS NOT NULL AND failed_at IS NULL)
    OR (state IN ('invalid_model_output', 'provider_failed') AND started_at IS NOT NULL AND completed_at IS NULL AND failed_at IS NOT NULL)
  ),
  CONSTRAINT source_analysis_attempts_failure_details_consistent CHECK (
    (state IN ('queued', 'running', 'succeeded') AND safe_error_category IS NULL AND safe_error_code IS NULL)
    OR (state IN ('invalid_model_output', 'provider_failed') AND safe_error_category IS NOT NULL AND safe_error_code IS NOT NULL)
  )
);

CREATE INDEX source_analysis_attempts_run_created_idx
  ON public.source_analysis_attempts (org_id, source_analysis_run_id, attempt_number);
CREATE INDEX source_analysis_attempts_open_idx
  ON public.source_analysis_attempts (org_id, state, created_at)
  WHERE state IN ('queued', 'running');

-- New inserts remain compatible with the completed validation worker while
-- giving new extraction writers an explicit, immutable idempotency key.
CREATE FUNCTION public.source_analysis_provenance_default_idempotency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.idempotency_key IS NULL THEN
    NEW.idempotency_key := NEW.request_key;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER source_analysis_runs_default_idempotency
  BEFORE INSERT ON public.source_analysis_runs
  FOR EACH ROW EXECUTE FUNCTION public.source_analysis_provenance_default_idempotency();

CREATE FUNCTION public.source_analysis_provenance_supersession_asset_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE superseded_asset_id uuid;
DECLARE superseded_created_at timestamptz;
DECLARE creates_cycle boolean;
BEGIN
  IF NEW.superseded_by_run_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT asset_id, created_at INTO superseded_asset_id, superseded_created_at
  FROM public.source_analysis_runs
  WHERE org_id = NEW.org_id AND id = NEW.superseded_by_run_id;
  IF superseded_asset_id IS NULL OR superseded_asset_id IS DISTINCT FROM NEW.asset_id THEN
    RAISE EXCEPTION 'source analysis supersession must remain asset scoped';
  END IF;
  IF superseded_created_at < NEW.created_at THEN
    RAISE EXCEPTION 'source analysis supersession cannot point to an older run';
  END IF;
  WITH RECURSIVE lineage(run_id, depth) AS (
    SELECT NEW.superseded_by_run_id, 1
    UNION ALL
    SELECT parent.superseded_by_run_id, lineage.depth + 1
    FROM public.source_analysis_runs AS parent
    JOIN lineage ON lineage.run_id = parent.id
    WHERE parent.org_id = NEW.org_id
      AND parent.asset_id = NEW.asset_id
      AND parent.superseded_by_run_id IS NOT NULL
      AND lineage.depth < 1000
  )
  SELECT EXISTS (SELECT 1 FROM lineage WHERE run_id = NEW.id) INTO creates_cycle;
  IF creates_cycle THEN
    RAISE EXCEPTION 'source analysis supersession cannot create a cycle';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER source_analysis_runs_supersession_asset_consistent
  BEFORE INSERT OR UPDATE OF org_id, asset_id, superseded_by_run_id ON public.source_analysis_runs
  FOR EACH ROW EXECUTE FUNCTION public.source_analysis_provenance_supersession_asset_guard();

CREATE FUNCTION public.source_analysis_provenance_run_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE terminal boolean;
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.org_id IS DISTINCT FROM OLD.org_id
     OR NEW.asset_id IS DISTINCT FROM OLD.asset_id
     OR NEW.request_key IS DISTINCT FROM OLD.request_key
     OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
     OR NEW.analysis_kind IS DISTINCT FROM OLD.analysis_kind
     OR NEW.page_content_version IS DISTINCT FROM OLD.page_content_version
     OR NEW.provider IS DISTINCT FROM OLD.provider
     OR NEW.model_identifier IS DISTINCT FROM OLD.model_identifier
     OR NEW.model_config_version IS DISTINCT FROM OLD.model_config_version
     OR NEW.prompt_version IS DISTINCT FROM OLD.prompt_version
     OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.catalogue_version IS DISTINCT FROM OLD.catalogue_version
     OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'source analysis provenance identity is immutable';
  END IF;

  terminal := CASE
    WHEN OLD.analysis_kind = 'ai_extraction'
      THEN OLD.analysis_state IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required')
    ELSE OLD.state IN ('succeeded', 'failed')
  END;
  IF terminal THEN
    RAISE EXCEPTION 'terminal source analysis runs are immutable';
  END IF;

  IF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'queued'
     AND NEW.analysis_state NOT IN ('queued', 'running') THEN
    RAISE EXCEPTION 'source analysis run must be claimed before completion';
  ELSIF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'running'
     AND NEW.analysis_state = 'queued' THEN
    IF OLD.lease_expires_at IS NULL OR OLD.lease_expires_at > now()
       OR NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.failed_at IS NOT NULL
       OR NEW.lease_token IS NOT NULL OR NEW.lease_expires_at IS NOT NULL THEN
      RAISE EXCEPTION 'source analysis run may be replayed only after its lease expires';
    END IF;
  ELSIF OLD.analysis_kind = 'ai_extraction' AND OLD.analysis_state = 'running'
     AND NEW.analysis_state NOT IN ('running', 'validated', 'invalid_model_output', 'provider_failed', 'review_required') THEN
    RAISE EXCEPTION 'invalid source analysis run transition';
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'queued' AND NEW.state NOT IN ('queued', 'running') THEN
    RAISE EXCEPTION 'source analysis run must be claimed before completion';
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'running' AND NEW.state = 'queued' THEN
    IF OLD.lease_expires_at IS NULL OR OLD.lease_expires_at > now()
       OR NEW.started_at IS NOT NULL OR NEW.completed_at IS NOT NULL OR NEW.failed_at IS NOT NULL
       OR NEW.lease_token IS NOT NULL OR NEW.lease_expires_at IS NOT NULL THEN
      RAISE EXCEPTION 'source analysis run may be replayed only after its lease expires';
    END IF;
  ELSIF OLD.analysis_kind = 'asset_validation' AND OLD.state = 'running'
     AND NEW.state NOT IN ('running', 'succeeded', 'failed') THEN
    RAISE EXCEPTION 'invalid source analysis run transition';
  END IF;

  IF OLD.analysis_kind = 'ai_extraction'
     AND OLD.analysis_state = 'running'
     AND NEW.analysis_state IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required') THEN
    IF OLD.lease_token IS NULL OR OLD.lease_expires_at IS NULL OR OLD.lease_expires_at <= now() THEN
      RAISE EXCEPTION 'source analysis terminal transition requires an active lease';
    END IF;
    -- The current fence remains attached to the immutable terminal row. A
    -- service command must prove it owns this token before issuing the update;
    -- no direct table privilege exists for callers to bypass that boundary.
    IF NEW.lease_token IS DISTINCT FROM OLD.lease_token
       OR NEW.lease_expires_at IS DISTINCT FROM OLD.lease_expires_at THEN
      RAISE EXCEPTION 'source analysis terminal transition must retain its active lease fence';
    END IF;
  END IF;

  IF OLD.provider_request_id IS NOT NULL AND NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id THEN
    RAISE EXCEPTION 'source analysis provider request identity is immutable';
  END IF;
  IF OLD.provider_operation_id IS NOT NULL AND NEW.provider_operation_id IS DISTINCT FROM OLD.provider_operation_id THEN
    RAISE EXCEPTION 'source analysis provider operation identity is immutable';
  END IF;
  IF OLD.superseded_by_run_id IS NOT NULL AND NEW.superseded_by_run_id IS DISTINCT FROM OLD.superseded_by_run_id THEN
    RAISE EXCEPTION 'source analysis supersession is immutable';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER source_analysis_runs_provenance_transition_guard
  BEFORE UPDATE ON public.source_analysis_runs
  FOR EACH ROW EXECUTE FUNCTION public.source_analysis_provenance_run_transition_guard();

CREATE FUNCTION public.source_analysis_provenance_attempt_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE run_kind public.source_analysis_kind;
DECLARE run_state public.source_analysis_provenance_state;
DECLARE previous_attempt public.source_analysis_attempts%ROWTYPE;
DECLARE terminal boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Lock the parent run so concurrent retry writers cannot both decide they
    -- own the next ordinal. Attempts are append-only and the run is the
    -- serialization point for bounded retry sequencing.
    SELECT analysis_kind, analysis_state INTO run_kind, run_state
    FROM public.source_analysis_runs
    WHERE org_id = NEW.org_id AND id = NEW.source_analysis_run_id
    FOR UPDATE;
    IF run_kind IS DISTINCT FROM 'ai_extraction'::public.source_analysis_kind THEN
      RAISE EXCEPTION 'analysis attempts require an ai extraction run';
    END IF;
    IF run_state IN ('validated', 'invalid_model_output', 'provider_failed', 'review_required') THEN
      RAISE EXCEPTION 'analysis attempts cannot be appended to a terminal run';
    END IF;
    IF NEW.attempt_number NOT BETWEEN 1 AND 3 THEN
      RAISE EXCEPTION 'source analysis attempts are capped at three total attempts';
    END IF;
    IF NEW.attempt_number = 1 THEN
      IF NEW.retry_reason <> 'initial' THEN
        RAISE EXCEPTION 'first source analysis attempt must be initial';
      END IF;
    ELSE
      SELECT * INTO previous_attempt
      FROM public.source_analysis_attempts
      WHERE source_analysis_run_id = NEW.source_analysis_run_id
        AND attempt_number = NEW.attempt_number - 1;
      IF previous_attempt.id IS NULL
         OR previous_attempt.state NOT IN ('invalid_model_output', 'provider_failed') THEN
        RAISE EXCEPTION 'source analysis retry requires the immediately prior terminal attempt';
      END IF;
      IF NEW.retry_reason = 'initial' THEN
        RAISE EXCEPTION 'source analysis retry cannot use the initial reason';
      ELSIF NEW.retry_reason = 'invalid_output_regeneration'
        AND previous_attempt.state <> 'invalid_model_output' THEN
        RAISE EXCEPTION 'invalid-output regeneration requires invalid model output';
      ELSIF NEW.retry_reason IN ('transient_retry', 'operator_recovery')
        AND previous_attempt.state <> 'provider_failed' THEN
        RAISE EXCEPTION 'provider retry requires a provider failure';
      END IF;
      IF NEW.attempt_number = 3 THEN
        IF NEW.retry_reason <> 'transient_retry'
           OR previous_attempt.retry_reason <> 'transient_retry'
           OR EXISTS (
             SELECT 1 FROM public.source_analysis_attempts AS earlier
             WHERE earlier.source_analysis_run_id = NEW.source_analysis_run_id
               AND earlier.state = 'invalid_model_output'
           ) THEN
          RAISE EXCEPTION 'third source analysis attempt is reserved for the second transient retry';
        END IF;
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.org_id IS DISTINCT FROM OLD.org_id
     OR NEW.source_analysis_run_id IS DISTINCT FROM OLD.source_analysis_run_id
     OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
     OR NEW.retry_reason IS DISTINCT FROM OLD.retry_reason
     OR NEW.provider IS DISTINCT FROM OLD.provider
     OR NEW.model_identifier IS DISTINCT FROM OLD.model_identifier
     OR NEW.model_config_version IS DISTINCT FROM OLD.model_config_version
     OR NEW.prompt_version IS DISTINCT FROM OLD.prompt_version
     OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
     OR NEW.catalogue_version IS DISTINCT FROM OLD.catalogue_version
     OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'source analysis attempt identity is immutable';
  END IF;

  terminal := OLD.state IN ('succeeded', 'invalid_model_output', 'provider_failed');
  IF terminal THEN
    RAISE EXCEPTION 'terminal source analysis attempts are immutable';
  END IF;
  IF OLD.state = 'queued' AND NEW.state NOT IN ('queued', 'running') THEN
    RAISE EXCEPTION 'source analysis attempt must start before completion';
  ELSIF OLD.state = 'running' AND NEW.state NOT IN ('running', 'succeeded', 'invalid_model_output', 'provider_failed') THEN
    RAISE EXCEPTION 'invalid source analysis attempt transition';
  END IF;
  IF OLD.provider_request_id IS NOT NULL AND NEW.provider_request_id IS DISTINCT FROM OLD.provider_request_id THEN
    RAISE EXCEPTION 'source analysis attempt provider request identity is immutable';
  END IF;
  IF OLD.provider_operation_id IS NOT NULL AND NEW.provider_operation_id IS DISTINCT FROM OLD.provider_operation_id THEN
    RAISE EXCEPTION 'source analysis attempt provider operation identity is immutable';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER source_analysis_attempts_provenance_guard
  BEFORE INSERT OR UPDATE ON public.source_analysis_attempts
  FOR EACH ROW EXECUTE FUNCTION public.source_analysis_provenance_attempt_guard();

CREATE FUNCTION public.source_analysis_provenance_prevent_attempt_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'source analysis attempts are retained until the authorised purge boundary';
END $$;

CREATE TRIGGER source_analysis_attempts_no_delete
  BEFORE DELETE ON public.source_analysis_attempts
  FOR EACH ROW EXECUTE FUNCTION public.source_analysis_provenance_prevent_attempt_delete();

ALTER TABLE public.source_analysis_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.source_analysis_attempts FORCE ROW LEVEL SECURITY;

-- There is no browser table/API surface for provenance. Existing source-run
-- workers already use service-only security-definer commands; this foundation
-- does not introduce a second direct table authority for runs or attempts.
REVOKE ALL ON TABLE public.source_analysis_runs, public.source_analysis_attempts
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.source_analysis_provenance_default_idempotency(),
  public.source_analysis_provenance_supersession_asset_guard(),
  public.source_analysis_provenance_run_transition_guard(),
  public.source_analysis_provenance_attempt_guard(),
  public.source_analysis_provenance_prevent_attempt_delete()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.source_analysis_runs IS
  'Asset-scoped, immutable-identity analysis runs. request_key/idempotency_key is the durable command identity; browser roles have no direct access.';
COMMENT ON TABLE public.source_analysis_attempts IS
  'Append-only provider attempt journal for AI extraction runs. Contains only safe identifiers, categories, usage, cost, latency, and timestamps; raw model output is intentionally out of scope.';

COMMIT;
