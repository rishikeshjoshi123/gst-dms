-- Immutable human field decisions and the service-owned effective metadata
-- projection. This keeps provenance-bearing candidates as the only automatic
-- input and does not migrate any consumer, provider worker, raw output, or UI.
BEGIN;

CREATE TYPE public.document_field_decision_action AS ENUM (
  'accepted',
  'corrected',
  'rejected',
  'cleared'
);

CREATE TYPE public.document_effective_metadata_resolution AS ENUM (
  'automatic',
  'accepted',
  'corrected',
  'rejected',
  'cleared'
);

-- `created_at` is transaction-scoped in PostgreSQL, so it cannot order two
-- candidates produced by one materialization statement. Keep a database-owned
-- sequence as the sole automatic-winner recency source.
ALTER TABLE public.document_field_candidates
  ADD COLUMN materialization_sequence bigint GENERATED ALWAYS AS IDENTITY;
ALTER TABLE public.document_field_candidates
  ALTER COLUMN materialization_sequence SET NOT NULL,
  ADD CONSTRAINT document_field_candidates_materialization_sequence_unique
    UNIQUE (materialization_sequence);

-- Decisions are consequential human metadata changes. Keep their authority in
-- the canonical membership capability matrix, rather than treating a client
-- supplied actor identifier as permission.
CREATE OR REPLACE FUNCTION public.organisation_member_capabilities(
  p_role public.org_member_role,
  p_is_owner boolean,
  p_state public.organisation_membership_state
)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE
    WHEN p_state <> 'active' THEN ARRAY[]::text[]
    WHEN p_is_owner THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','team.invite.admin','team.role.manage_admin',
      'team.membership.manage_admin','team.ownership.transfer','trash.purge',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide'
    ]::text[]
    WHEN p_role='admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','document.view',
      'document.intake.create','document.record.create','document.intake.assign',
      'document.intake.discard','document.version.attach','document.version.replace',
      'document.reprocess','document.metadata.decide'
    ]::text[]
    WHEN p_role='associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide'
    ]::text[]
    ELSE ARRAY['team.view','document.view']::text[] END
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = pg_catalog, public AS $$
  SELECT m.id,m.org_id,m.role,(o.owner_membership_id=m.id),m.state,6,
    public.organisation_member_capabilities(m.role,o.owner_membership_id=m.id,m.state),m.revision
  FROM public.organisation_memberships AS m
  JOIN public.organisations AS o ON o.id=m.org_id
  WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended')
$$;

CREATE FUNCTION public.document_field_decision_reason_is_safe(p_reason text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_reason IS NULL OR (
    char_length(p_reason) BETWEEN 1 AND 500
    AND p_reason !~ '[[:cntrl:]]'
  )
$$;

CREATE FUNCTION public.document_field_decision_actor_is_authorised(
  p_org_id uuid,
  p_actor_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT p_org_id IS NOT NULL
    AND p_actor_user_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.organisation_memberships AS membership
      JOIN public.organisations AS organisation
        ON organisation.id = membership.org_id
      WHERE membership.org_id = p_org_id
        AND membership.user_id = p_actor_user_id
        AND membership.state = 'active'::public.organisation_membership_state
        AND 'document.metadata.decide' = ANY(
          public.organisation_member_capabilities(
            membership.role,
            organisation.owner_membership_id = membership.id,
            membership.state
          )
        )
    )
$$;

CREATE TABLE public.document_field_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  document_field_candidate_id uuid NOT NULL,
  semantic_candidate_key text NOT NULL,
  field_path text NOT NULL,
  value_type public.source_field_candidate_value_type NOT NULL,
  action public.document_field_decision_action NOT NULL,
  replacement_value jsonb,
  reason text,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_field_decisions_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_field_decisions_document_org_fkey
    FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_decisions_version_org_fkey
    FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_decisions_candidate_org_fkey
    FOREIGN KEY (org_id, document_field_candidate_id)
    REFERENCES public.document_field_candidates(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_field_decisions_actor_request_unique
    UNIQUE (org_id, actor_user_id, idempotency_key),
  CONSTRAINT document_field_decisions_safe_identity CHECK (
    semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
    AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
    AND idempotency_key ~ '^[a-z][a-z0-9_.:-]{0,127}$'
  ),
  CONSTRAINT document_field_decisions_replacement_safe CHECK (
    replacement_value IS NULL
    OR public.source_field_candidate_normalized_value_is_valid(value_type, replacement_value)
  ),
  CONSTRAINT document_field_decisions_action_consistent CHECK (
    (action = 'corrected'::public.document_field_decision_action AND replacement_value IS NOT NULL)
    OR (action <> 'corrected'::public.document_field_decision_action AND replacement_value IS NULL)
  ),
  CONSTRAINT document_field_decisions_reason_safe CHECK (
    public.document_field_decision_reason_is_safe(reason)
  )
);

CREATE INDEX document_field_decisions_document_version_latest_idx
  ON public.document_field_decisions (
    org_id, document_id, document_version_id, field_path,
    semantic_candidate_key, decision_sequence DESC
  );
CREATE INDEX document_field_decisions_candidate_idx
  ON public.document_field_decisions (org_id, document_field_candidate_id, decision_sequence DESC);

-- The command owns the candidate-derived identity fields. This trigger is a
-- second fence for privileged callers and verifies exact tenant, document, and
-- immutable-version compatibility before a decision can become audit history.
CREATE FUNCTION public.document_field_decision_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  candidate_row public.document_field_candidates%ROWTYPE;
  version_document_id uuid;
  version_validation_state public.document_version_validation_state;
  version_state public.document_version_state;
BEGIN
  SELECT document_id, validation_state, state
    INTO version_document_id, version_validation_state, version_state
  FROM public.document_versions
  WHERE org_id = NEW.org_id AND id = NEW.document_version_id
  FOR KEY SHARE;
  SELECT * INTO candidate_row
  FROM public.document_field_candidates
  WHERE org_id = NEW.org_id AND id = NEW.document_field_candidate_id
  FOR KEY SHARE;

  IF candidate_row.id IS NULL
     OR version_document_id IS NULL
     OR NEW.document_id IS DISTINCT FROM version_document_id
     OR candidate_row.document_id IS DISTINCT FROM NEW.document_id
     OR candidate_row.document_version_id IS DISTINCT FROM NEW.document_version_id
     OR version_validation_state <> 'valid'::public.document_version_validation_state
     OR version_state NOT IN ('current'::public.document_version_state, 'superseded'::public.document_version_state) THEN
    RAISE EXCEPTION 'document field decision must reference one compatible tenant document version and candidate';
  END IF;

  NEW.semantic_candidate_key := candidate_row.semantic_candidate_key;
  NEW.field_path := candidate_row.field_path;
  NEW.value_type := candidate_row.value_type;

  IF NEW.action = 'accepted'::public.document_field_decision_action
     AND candidate_row.validation_state = 'invalid'::public.source_field_candidate_validation_state THEN
    RAISE EXCEPTION 'invalid document candidate cannot be accepted as effective metadata';
  END IF;

  IF NOT public.document_field_decision_actor_is_authorised(
    NEW.org_id, NEW.actor_user_id
  ) THEN
    RAISE EXCEPTION 'document field decision actor must be an active authorised organisation member';
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER document_field_decisions_insert_guard
  BEFORE INSERT ON public.document_field_decisions
  FOR EACH ROW EXECUTE FUNCTION public.document_field_decision_insert_guard();

CREATE FUNCTION public.document_field_decision_immutable_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RAISE EXCEPTION 'document field decisions are append-only and immutable';
END $$;

CREATE TRIGGER document_field_decisions_no_update
  BEFORE UPDATE ON public.document_field_decisions
  FOR EACH ROW EXECUTE FUNCTION public.document_field_decision_immutable_guard();
CREATE TRIGGER document_field_decisions_no_delete
  BEFORE DELETE ON public.document_field_decisions
  FOR EACH ROW EXECUTE FUNCTION public.document_field_decision_immutable_guard();

-- This table is a rebuildable, service-only projection. It records its winning
-- decision/candidate rather than becoming a second editable metadata source.
CREATE TABLE public.document_effective_metadata (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  semantic_candidate_key text NOT NULL,
  field_path text NOT NULL,
  value_type public.source_field_candidate_value_type NOT NULL,
  normalized_value jsonb,
  resolution public.document_effective_metadata_resolution NOT NULL,
  winning_document_field_candidate_id uuid NOT NULL,
  winning_document_field_decision_id uuid,
  computed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_effective_metadata_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_effective_metadata_document_org_fkey
    FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_effective_metadata_version_org_fkey
    FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_effective_metadata_candidate_org_fkey
    FOREIGN KEY (org_id, winning_document_field_candidate_id)
    REFERENCES public.document_field_candidates(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_effective_metadata_decision_org_fkey
    FOREIGN KEY (org_id, winning_document_field_decision_id)
    REFERENCES public.document_field_decisions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_effective_metadata_version_key_unique
    UNIQUE (document_version_id, field_path, semantic_candidate_key),
  CONSTRAINT document_effective_metadata_safe_identity CHECK (
    semantic_candidate_key ~ '^[a-z][a-z0-9_.:-]{0,199}$'
    AND field_path ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){0,15}$'
  ),
  CONSTRAINT document_effective_metadata_value_safe CHECK (
    normalized_value IS NULL
    OR public.source_field_candidate_normalized_value_is_valid(value_type, normalized_value)
  ),
  CONSTRAINT document_effective_metadata_resolution_consistent CHECK (
    (resolution = 'automatic'::public.document_effective_metadata_resolution
      AND winning_document_field_decision_id IS NULL AND normalized_value IS NOT NULL)
    OR (resolution IN ('accepted'::public.document_effective_metadata_resolution,
                       'corrected'::public.document_effective_metadata_resolution)
      AND winning_document_field_decision_id IS NOT NULL AND normalized_value IS NOT NULL)
    OR (resolution IN ('rejected'::public.document_effective_metadata_resolution,
                       'cleared'::public.document_effective_metadata_resolution)
      AND winning_document_field_decision_id IS NOT NULL AND normalized_value IS NULL)
  )
);

CREATE INDEX document_effective_metadata_document_version_idx
  ON public.document_effective_metadata (org_id, document_id, document_version_id, field_path);

CREATE FUNCTION public.document_effective_metadata_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  candidate_row public.document_field_candidates%ROWTYPE;
  decision_row public.document_field_decisions%ROWTYPE;
  version_document_id uuid;
BEGIN
  SELECT document_id INTO version_document_id
  FROM public.document_versions
  WHERE org_id = NEW.org_id AND id = NEW.document_version_id
  FOR KEY SHARE;
  SELECT * INTO candidate_row
  FROM public.document_field_candidates
  WHERE org_id = NEW.org_id AND id = NEW.winning_document_field_candidate_id
  FOR KEY SHARE;

  IF candidate_row.id IS NULL
     OR version_document_id IS NULL
     OR NEW.document_id IS DISTINCT FROM version_document_id
     OR candidate_row.document_id IS DISTINCT FROM NEW.document_id
     OR candidate_row.document_version_id IS DISTINCT FROM NEW.document_version_id
     OR NEW.semantic_candidate_key IS DISTINCT FROM candidate_row.semantic_candidate_key
     OR NEW.field_path IS DISTINCT FROM candidate_row.field_path
     OR NEW.value_type IS DISTINCT FROM candidate_row.value_type THEN
    RAISE EXCEPTION 'effective metadata winner must preserve one compatible document candidate and version';
  END IF;

  IF NEW.winning_document_field_decision_id IS NULL THEN
    IF NEW.resolution <> 'automatic'::public.document_effective_metadata_resolution
       OR candidate_row.validation_state <> 'eligible'::public.source_field_candidate_validation_state
       OR NEW.normalized_value IS DISTINCT FROM candidate_row.normalized_value THEN
      RAISE EXCEPTION 'automatic effective metadata requires its exact eligible candidate';
    END IF;
    RETURN NEW;
  END IF;

  SELECT * INTO decision_row
  FROM public.document_field_decisions
  WHERE org_id = NEW.org_id AND id = NEW.winning_document_field_decision_id
  FOR KEY SHARE;
  IF decision_row.id IS NULL
     OR decision_row.document_id IS DISTINCT FROM NEW.document_id
     OR decision_row.document_version_id IS DISTINCT FROM NEW.document_version_id
     OR decision_row.document_field_candidate_id IS DISTINCT FROM candidate_row.id
     OR decision_row.semantic_candidate_key IS DISTINCT FROM NEW.semantic_candidate_key
     OR decision_row.field_path IS DISTINCT FROM NEW.field_path
     OR decision_row.value_type IS DISTINCT FROM NEW.value_type
     OR NEW.resolution::text IS DISTINCT FROM decision_row.action::text THEN
    RAISE EXCEPTION 'effective metadata decision winner is incompatible with its document candidate';
  END IF;

  IF (decision_row.action = 'accepted'::public.document_field_decision_action
      AND (candidate_row.validation_state = 'invalid'::public.source_field_candidate_validation_state
        OR NEW.normalized_value IS DISTINCT FROM candidate_row.normalized_value))
     OR (decision_row.action = 'corrected'::public.document_field_decision_action
      AND NEW.normalized_value IS DISTINCT FROM decision_row.replacement_value)
     OR (decision_row.action IN ('rejected'::public.document_field_decision_action,
                                 'cleared'::public.document_field_decision_action)
      AND NEW.normalized_value IS NOT NULL) THEN
    RAISE EXCEPTION 'effective metadata value does not match its immutable winning provenance';
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER document_effective_metadata_insert_guard
  BEFORE INSERT ON public.document_effective_metadata
  FOR EACH ROW EXECUTE FUNCTION public.document_effective_metadata_insert_guard();

-- Rebuild the exact version projection from immutable decisions first, then
-- only eligible automatic candidates. A rejected or cleared human decision is
-- intentionally retained as the winner with no value, so it cannot silently
-- fall back to older automated output.
CREATE FUNCTION public.recompute_document_effective_metadata(
  p_document_version_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  version_row public.document_versions%ROWTYPE;
BEGIN
  IF p_document_version_id IS NULL THEN
    RAISE EXCEPTION 'document effective metadata recompute requires a document version';
  END IF;

  SELECT * INTO version_row
  FROM public.document_versions
  WHERE id = p_document_version_id
  FOR UPDATE;
  IF version_row.id IS NULL
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state
     OR version_row.state NOT IN ('current'::public.document_version_state, 'superseded'::public.document_version_state) THEN
    RAISE EXCEPTION 'document effective metadata recompute requires a valid immutable document version';
  END IF;

  DELETE FROM public.document_effective_metadata
  WHERE org_id = version_row.org_id
    AND document_id = version_row.document_id
    AND document_version_id = version_row.id;

  WITH candidate_keys AS (
    SELECT DISTINCT field_path, semantic_candidate_key
    FROM public.document_field_candidates
    WHERE org_id = version_row.org_id
      AND document_id = version_row.document_id
      AND document_version_id = version_row.id
  ),
  latest_decisions AS (
    SELECT DISTINCT ON (decision.field_path, decision.semantic_candidate_key)
      decision.id,
      decision.document_field_candidate_id,
      decision.field_path,
      decision.semantic_candidate_key,
      decision.value_type,
      decision.action,
      decision.replacement_value,
      candidate.normalized_value AS candidate_normalized_value,
      candidate.validation_state AS candidate_validation_state
    FROM public.document_field_decisions AS decision
    JOIN public.document_field_candidates AS candidate
      ON candidate.org_id = decision.org_id
      AND candidate.id = decision.document_field_candidate_id
    WHERE decision.org_id = version_row.org_id
      AND decision.document_id = version_row.document_id
      AND decision.document_version_id = version_row.id
    ORDER BY decision.field_path, decision.semantic_candidate_key,
      decision.decision_sequence DESC
  ),
  latest_eligible_candidates AS (
    SELECT DISTINCT ON (candidate.field_path, candidate.semantic_candidate_key)
      candidate.id,
      candidate.field_path,
      candidate.semantic_candidate_key,
      candidate.value_type,
      candidate.normalized_value
    FROM public.document_field_candidates AS candidate
    WHERE candidate.org_id = version_row.org_id
      AND candidate.document_id = version_row.document_id
      AND candidate.document_version_id = version_row.id
      AND candidate.validation_state = 'eligible'::public.source_field_candidate_validation_state
    ORDER BY candidate.field_path, candidate.semantic_candidate_key,
      candidate.materialization_sequence DESC
  )
  INSERT INTO public.document_effective_metadata(
    org_id, document_id, document_version_id, semantic_candidate_key, field_path,
    value_type, normalized_value, resolution,
    winning_document_field_candidate_id, winning_document_field_decision_id
  )
  SELECT
    version_row.org_id,
    version_row.document_id,
    version_row.id,
    keys.semantic_candidate_key,
    keys.field_path,
    COALESCE(decision.value_type, candidate.value_type),
    CASE
      WHEN decision.action = 'accepted'::public.document_field_decision_action
        THEN decision.candidate_normalized_value
      WHEN decision.action = 'corrected'::public.document_field_decision_action
        THEN decision.replacement_value
      WHEN decision.id IS NOT NULL THEN NULL
      ELSE candidate.normalized_value
    END,
    COALESCE(
      decision.action::text::public.document_effective_metadata_resolution,
      'automatic'::public.document_effective_metadata_resolution
    ),
    COALESCE(decision.document_field_candidate_id, candidate.id),
    decision.id
  FROM candidate_keys AS keys
  LEFT JOIN latest_decisions AS decision
    ON decision.field_path = keys.field_path
    AND decision.semantic_candidate_key = keys.semantic_candidate_key
  LEFT JOIN latest_eligible_candidates AS candidate
    ON candidate.field_path = keys.field_path
    AND candidate.semantic_candidate_key = keys.semantic_candidate_key
  WHERE decision.id IS NOT NULL OR candidate.id IS NOT NULL;
END $$;

-- The only human-decision mutation boundary. It validates the exact candidate
-- and actor, appends one immutable row, rebuilds its projection, and returns
-- the original row for an identical retry. A reused idempotency key cannot
-- silently represent a different legal decision.
CREATE FUNCTION public.record_document_field_decision(
  p_document_field_candidate_id uuid,
  p_action public.document_field_decision_action,
  p_replacement_value jsonb,
  p_reason text,
  p_actor_user_id uuid,
  p_idempotency_key text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  candidate_version_id uuid;
  version_row public.document_versions%ROWTYPE;
  candidate_row public.document_field_candidates%ROWTYPE;
  existing_decision public.document_field_decisions%ROWTYPE;
  decision_id uuid;
BEGIN
  IF p_document_field_candidate_id IS NULL
     OR p_action IS NULL
     OR p_actor_user_id IS NULL
     OR p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[a-z][a-z0-9_.:-]{0,127}$'
     OR NOT public.document_field_decision_reason_is_safe(p_reason) THEN
    RAISE EXCEPTION 'document field decision request is incomplete or unsafe';
  END IF;

  -- Materialization takes the version lock before it reaches document
  -- candidates. Follow that same lock order here: an initial immutable-ID
  -- lookup establishes the version, then all blocking locks are version-first.
  SELECT document_version_id INTO candidate_version_id
  FROM public.document_field_candidates
  WHERE id = p_document_field_candidate_id;
  IF candidate_version_id IS NULL THEN
    RAISE EXCEPTION 'document field decision requires a document candidate';
  END IF;

  SELECT * INTO version_row
  FROM public.document_versions
  WHERE id = candidate_version_id
  FOR UPDATE;
  IF version_row.id IS NULL
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state
     OR version_row.state NOT IN ('current'::public.document_version_state, 'superseded'::public.document_version_state) THEN
    RAISE EXCEPTION 'document field decision requires a valid immutable document version';
  END IF;

  SELECT * INTO candidate_row
  FROM public.document_field_candidates
  WHERE id = p_document_field_candidate_id
    AND document_version_id = version_row.id
  FOR KEY SHARE;
  IF candidate_row.id IS NULL THEN
    RAISE EXCEPTION 'document field decision requires a document candidate';
  END IF;
  IF NOT public.document_field_decision_actor_is_authorised(
    candidate_row.org_id, p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'document field decision actor must be an active authorised organisation member';
  END IF;
  IF p_action = 'corrected'::public.document_field_decision_action
     AND (p_replacement_value IS NULL
       OR NOT public.source_field_candidate_normalized_value_is_valid(
         candidate_row.value_type, p_replacement_value
       )) THEN
    RAISE EXCEPTION 'corrected document field decision requires a safe typed replacement value';
  END IF;
  IF p_action <> 'corrected'::public.document_field_decision_action
     AND p_replacement_value IS NOT NULL THEN
    RAISE EXCEPTION 'only corrected document field decisions may include a replacement value';
  END IF;

  SELECT * INTO existing_decision
  FROM public.document_field_decisions
  WHERE org_id = candidate_row.org_id
    AND actor_user_id = p_actor_user_id
    AND idempotency_key = p_idempotency_key
  FOR KEY SHARE;
  IF existing_decision.id IS NOT NULL THEN
    IF existing_decision.document_field_candidate_id IS DISTINCT FROM candidate_row.id
       OR existing_decision.action IS DISTINCT FROM p_action
       OR existing_decision.replacement_value IS DISTINCT FROM p_replacement_value
       OR existing_decision.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'document field decision idempotency key conflicts with immutable decision material';
    END IF;
    PERFORM public.recompute_document_effective_metadata(existing_decision.document_version_id);
    RETURN existing_decision.id;
  END IF;

  INSERT INTO public.document_field_decisions(
    org_id, document_id, document_version_id, document_field_candidate_id,
    semantic_candidate_key, field_path, value_type, action, replacement_value,
    reason, actor_user_id, idempotency_key
  ) VALUES (
    candidate_row.org_id, candidate_row.document_id, candidate_row.document_version_id,
    candidate_row.id, candidate_row.semantic_candidate_key, candidate_row.field_path,
    candidate_row.value_type, p_action, p_replacement_value, p_reason,
    p_actor_user_id, p_idempotency_key
  ) ON CONFLICT (org_id, actor_user_id, idempotency_key) DO NOTHING
  RETURNING id INTO decision_id;

  IF decision_id IS NULL THEN
    SELECT * INTO existing_decision
    FROM public.document_field_decisions
    WHERE org_id = candidate_row.org_id
      AND actor_user_id = p_actor_user_id
      AND idempotency_key = p_idempotency_key
    FOR KEY SHARE;
    IF existing_decision.id IS NULL
       OR existing_decision.document_field_candidate_id IS DISTINCT FROM candidate_row.id
       OR existing_decision.action IS DISTINCT FROM p_action
       OR existing_decision.replacement_value IS DISTINCT FROM p_replacement_value
       OR existing_decision.reason IS DISTINCT FROM p_reason THEN
      RAISE EXCEPTION 'document field decision idempotency key conflicts with immutable decision material';
    END IF;
    decision_id := existing_decision.id;
  END IF;

  PERFORM public.recompute_document_effective_metadata(candidate_row.document_version_id);
  RETURN decision_id;
END $$;

-- Binding materialization may insert an entire source-run comparison set at
-- once. Recompute once per affected version at statement completion so an
-- eligible candidate becomes effective without giving that materializer any
-- direct projection-table authority.
CREATE FUNCTION public.document_field_candidates_recompute_effective_metadata()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  affected_version_id uuid;
BEGIN
  FOR affected_version_id IN
    SELECT DISTINCT document_version_id FROM new_document_field_candidates
  LOOP
    PERFORM public.recompute_document_effective_metadata(affected_version_id);
  END LOOP;
  RETURN NULL;
END $$;

CREATE TRIGGER document_field_candidates_recompute_effective_metadata
  AFTER INSERT ON public.document_field_candidates
  REFERENCING NEW TABLE AS new_document_field_candidates
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.document_field_candidates_recompute_effective_metadata();

ALTER TABLE public.document_field_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_field_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_effective_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_effective_metadata FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.document_field_decisions, public.document_effective_metadata
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.document_field_decision_reason_is_safe(text),
  public.document_field_decision_actor_is_authorised(uuid, uuid),
  public.document_field_decision_insert_guard(),
  public.document_field_decision_immutable_guard(),
  public.document_effective_metadata_insert_guard(),
  public.document_field_candidates_recompute_effective_metadata(),
  public.recompute_document_effective_metadata(uuid),
  public.record_document_field_decision(
    uuid, public.document_field_decision_action, jsonb, text, uuid, text
  )
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recompute_document_effective_metadata(uuid)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.record_document_field_decision(
  uuid, public.document_field_decision_action, jsonb, text, uuid, text
) TO service_role;

REVOKE ALL ON FUNCTION public.organisation_member_capabilities(
  public.org_member_role, boolean, public.organisation_membership_state
) FROM PUBLIC, anon;

COMMENT ON TABLE public.document_field_decisions IS
  'Append-only human decisions over exact document-version candidates. Browser and direct service table access are denied.';
COMMENT ON TABLE public.document_effective_metadata IS
  'Service-owned rebuildable effective-metadata projection retaining the exact winning human decision or eligible automatic candidate.';
COMMENT ON FUNCTION public.recompute_document_effective_metadata(uuid) IS
  'Service-only idempotent recompute of one immutable document-version effective metadata projection.';
COMMENT ON FUNCTION public.record_document_field_decision(uuid, public.document_field_decision_action, jsonb, text, uuid, text) IS
  'Service-only idempotent append of an authorised human field decision followed by effective-metadata recompute.';

COMMIT;
