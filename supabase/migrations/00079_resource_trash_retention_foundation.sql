-- Hierarchical Resource Trash, Retention, and Purge foundation.
--
-- This is a prerequisite contract only. It intentionally exposes no trash,
-- restore, or purge command: later migrations own authorisation, transitions,
-- outbox effects, and physical cleanup.
BEGIN;

CREATE TYPE public.trash_resource_type AS ENUM ('client', 'matter', 'document');
CREATE TYPE public.resource_record_state AS ENUM ('active', 'trashed', 'purging', 'purged');
CREATE TYPE public.trash_operation_state AS ENUM (
  'trashed', 'restore_blocked', 'restoring', 'purge_scheduled',
  'purging', 'purge_failed', 'restored', 'purged'
);
CREATE TYPE public.resource_trash_cause AS ENUM ('direct', 'inherited');
CREATE TYPE public.resource_trash_membership_state AS ENUM (
  'active', 'restoring', 'purging', 'restored', 'purged'
);
CREATE TYPE public.trash_retention_mode AS ENUM ('manual_only', 'retention_period');
CREATE TYPE public.resource_hold_scope AS ENUM ('resource', 'subtree');
CREATE TYPE public.resource_hold_state AS ENUM ('active', 'released');

-- Document lifecycle introduced its own type before hierarchy-wide lifecycle
-- state existed. Keep its public type stable and add only the approved states.
ALTER TYPE public.document_record_state ADD VALUE IF NOT EXISTS 'purging';
ALTER TYPE public.document_record_state ADD VALUE IF NOT EXISTS 'purged';

-- Existing client/matter rows have no lifecycle state. Preserve deleted_at as
-- the compatibility signal; a later legacy migration will create synthetic
-- trash operations for retained rows with no membership reference.
ALTER TABLE public.clients
  ADD COLUMN record_state public.resource_record_state NOT NULL DEFAULT 'active',
  ADD COLUMN active_trash_membership_id uuid,
  ADD CONSTRAINT clients_org_id_id_unique UNIQUE (org_id, id);

ALTER TABLE public.matters
  ADD COLUMN record_state public.resource_record_state NOT NULL DEFAULT 'active',
  ADD COLUMN active_trash_membership_id uuid;

ALTER TABLE public.documents
  DROP CONSTRAINT documents_record_state_timestamps,
  ADD COLUMN active_trash_membership_id uuid;

UPDATE public.clients
SET record_state = CASE WHEN deleted_at IS NULL THEN 'active'::public.resource_record_state ELSE 'trashed'::public.resource_record_state END;
UPDATE public.matters
SET record_state = CASE WHEN deleted_at IS NULL THEN 'active'::public.resource_record_state ELSE 'trashed'::public.resource_record_state END;
UPDATE public.documents
SET record_state = CASE WHEN deleted_at IS NULL THEN 'active'::public.document_record_state ELSE 'trashed'::public.document_record_state END,
    trashed_at = COALESCE(trashed_at, deleted_at)
WHERE deleted_at IS NOT NULL;

ALTER TABLE public.clients ADD CONSTRAINT clients_trash_state_compatibility CHECK (
  -- Legacy actions still write only deleted_at until their command cut-over.
  (record_state = 'active' AND active_trash_membership_id IS NULL)
  OR (record_state = 'trashed' AND (deleted_at IS NOT NULL OR active_trash_membership_id IS NOT NULL))
  OR (record_state = 'purging' AND active_trash_membership_id IS NOT NULL)
  OR (record_state = 'purged' AND active_trash_membership_id IS NULL)
);
ALTER TABLE public.matters ADD CONSTRAINT matters_trash_state_compatibility CHECK (
  (record_state = 'active' AND active_trash_membership_id IS NULL)
  OR (record_state = 'trashed' AND (deleted_at IS NOT NULL OR active_trash_membership_id IS NOT NULL))
  OR (record_state = 'purging' AND active_trash_membership_id IS NOT NULL)
  OR (record_state = 'purged' AND active_trash_membership_id IS NULL)
);
ALTER TABLE public.documents ADD CONSTRAINT documents_trash_state_compatibility CHECK (
  (record_state::text = 'active' AND active_trash_membership_id IS NULL AND trashed_at IS NULL)
  OR (record_state::text = 'trashed' AND trashed_at IS NOT NULL
    AND (deleted_at IS NOT NULL OR active_trash_membership_id IS NOT NULL))
  OR (record_state::text = 'purging' AND trashed_at IS NOT NULL AND active_trash_membership_id IS NOT NULL)
  OR (record_state::text = 'purged' AND trashed_at IS NOT NULL AND active_trash_membership_id IS NULL)
);

CREATE TABLE public.organisation_retention_settings (
  org_id uuid PRIMARY KEY REFERENCES public.organisations(id) ON DELETE RESTRICT,
  trash_retention_mode public.trash_retention_mode NOT NULL DEFAULT 'manual_only',
  trash_retention_days smallint,
  auto_purge_enabled boolean NOT NULL DEFAULT false,
  policy_version integer NOT NULL DEFAULT 1 CHECK (policy_version >= 1),
  updated_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organisation_retention_settings_policy CHECK (
    (trash_retention_mode = 'manual_only' AND trash_retention_days IS NULL AND NOT auto_purge_enabled)
    OR (trash_retention_mode = 'retention_period' AND trash_retention_days IN (30, 60, 90, 180, 365))
  )
);

CREATE TABLE public.trash_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  root_resource_type public.trash_resource_type NOT NULL,
  root_resource_id uuid NOT NULL,
  root_client_id uuid,
  root_matter_id uuid,
  root_document_id uuid,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  reason text,
  idempotency_key text,
  state public.trash_operation_state NOT NULL DEFAULT 'trashed',
  retention_mode public.trash_retention_mode NOT NULL DEFAULT 'manual_only',
  retention_days smallint,
  auto_purge_enabled_snapshot boolean NOT NULL DEFAULT false,
  retention_policy_version integer NOT NULL DEFAULT 1 CHECK (retention_policy_version >= 1),
  purge_eligible_at timestamptz,
  auto_purge_at timestamptz,
  included_client_count integer NOT NULL DEFAULT 0 CHECK (included_client_count >= 0),
  included_matter_count integer NOT NULL DEFAULT 0 CHECK (included_matter_count >= 0),
  included_document_count integer NOT NULL DEFAULT 0 CHECK (included_document_count >= 0),
  unique_storage_bytes bigint NOT NULL DEFAULT 0 CHECK (unique_storage_bytes >= 0),
  shared_storage_bytes_retained bigint NOT NULL DEFAULT 0 CHECK (shared_storage_bytes_retained >= 0),
  preexisting_trashed_descendant_count integer NOT NULL DEFAULT 0 CHECK (preexisting_trashed_descendant_count >= 0),
  blocker_count integer NOT NULL DEFAULT 0 CHECK (blocker_count >= 0),
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  restore_blocked_at timestamptz,
  restore_started_at timestamptz,
  restored_at timestamptz,
  purge_scheduled_at timestamptz,
  purge_started_at timestamptz,
  purge_failed_at timestamptz,
  purged_at timestamptz,
  CONSTRAINT trash_operations_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT trash_operations_root_client_org_fkey FOREIGN KEY (org_id, root_client_id)
    REFERENCES public.clients(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_operations_root_matter_org_fkey FOREIGN KEY (org_id, root_matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_operations_root_document_org_fkey FOREIGN KEY (org_id, root_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT trash_operations_root_locator CHECK (
    (root_resource_type = 'client' AND root_client_id = root_resource_id AND root_matter_id IS NULL AND root_document_id IS NULL)
    OR (root_resource_type = 'matter' AND root_matter_id = root_resource_id AND root_client_id IS NULL AND root_document_id IS NULL)
    OR (root_resource_type = 'document' AND root_document_id = root_resource_id AND root_client_id IS NULL AND root_matter_id IS NULL)
  ),
  CONSTRAINT trash_operations_retention_snapshot CHECK (
    (retention_mode = 'manual_only' AND retention_days IS NULL AND NOT auto_purge_enabled_snapshot
      AND purge_eligible_at IS NULL AND auto_purge_at IS NULL)
    OR (retention_mode = 'retention_period' AND retention_days IN (30, 60, 90, 180, 365)
      AND purge_eligible_at IS NOT NULL
      AND ((auto_purge_enabled_snapshot AND auto_purge_at = purge_eligible_at)
        OR (NOT auto_purge_enabled_snapshot AND auto_purge_at IS NULL)))
  ),
  CONSTRAINT trash_operations_state_timestamps CHECK (
    (state = 'trashed' AND restore_blocked_at IS NULL AND restore_started_at IS NULL AND restored_at IS NULL
      AND purge_scheduled_at IS NULL AND purge_started_at IS NULL AND purge_failed_at IS NULL AND purged_at IS NULL)
    OR (state = 'restore_blocked' AND restore_blocked_at IS NOT NULL AND restore_started_at IS NULL AND restored_at IS NULL
      AND purge_scheduled_at IS NULL AND purge_started_at IS NULL AND purge_failed_at IS NULL AND purged_at IS NULL)
    OR (state = 'restoring' AND restore_started_at IS NOT NULL AND restored_at IS NULL
      AND purge_scheduled_at IS NULL AND purge_started_at IS NULL AND purge_failed_at IS NULL AND purged_at IS NULL)
    OR (state = 'restored' AND restored_at IS NOT NULL AND purge_scheduled_at IS NULL
      AND purge_started_at IS NULL AND purge_failed_at IS NULL AND purged_at IS NULL)
    OR (state = 'purge_scheduled' AND purge_scheduled_at IS NOT NULL AND restore_started_at IS NULL
      AND restored_at IS NULL AND purge_started_at IS NULL AND purge_failed_at IS NULL AND purged_at IS NULL)
    OR (state = 'purging' AND purge_started_at IS NOT NULL AND restored_at IS NULL AND purged_at IS NULL)
    OR (state = 'purge_failed' AND purge_started_at IS NOT NULL AND purge_failed_at IS NOT NULL
      AND restored_at IS NULL AND purged_at IS NULL)
    OR (state = 'purged' AND purge_started_at IS NOT NULL AND purged_at IS NOT NULL AND restored_at IS NULL)
  )
);
CREATE UNIQUE INDEX trash_operations_org_idempotency_key_unique
  ON public.trash_operations(org_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE public.resource_trash_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  resource_type public.trash_resource_type NOT NULL,
  resource_id uuid NOT NULL,
  client_id uuid,
  matter_id uuid,
  document_id uuid,
  parent_membership_id uuid,
  cause public.resource_trash_cause NOT NULL,
  prior_record_state public.resource_record_state NOT NULL DEFAULT 'active',
  state public.resource_trash_membership_state NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  restored_at timestamptz,
  purged_at timestamptz,
  CONSTRAINT resource_trash_memberships_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT resource_trash_memberships_operation_org_fkey FOREIGN KEY (org_id, operation_id)
    REFERENCES public.trash_operations(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_trash_memberships_client_org_fkey FOREIGN KEY (org_id, client_id)
    REFERENCES public.clients(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_trash_memberships_matter_org_fkey FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_trash_memberships_document_org_fkey FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_trash_memberships_parent_org_fkey FOREIGN KEY (org_id, parent_membership_id)
    REFERENCES public.resource_trash_memberships(org_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT resource_trash_memberships_locator CHECK (
    (resource_type = 'client' AND client_id = resource_id AND matter_id IS NULL AND document_id IS NULL)
    OR (resource_type = 'matter' AND matter_id = resource_id AND client_id IS NULL AND document_id IS NULL)
    OR (resource_type = 'document' AND document_id = resource_id AND client_id IS NULL AND matter_id IS NULL)
  ),
  CONSTRAINT resource_trash_memberships_cause_parent CHECK (
    (cause = 'direct' AND parent_membership_id IS NULL)
    OR (cause = 'inherited' AND parent_membership_id IS NOT NULL)
  ),
  CONSTRAINT resource_trash_memberships_terminal_timestamps CHECK (
    (state IN ('active', 'restoring', 'purging') AND restored_at IS NULL AND purged_at IS NULL)
    OR (state = 'restored' AND restored_at IS NOT NULL AND purged_at IS NULL)
    OR (state = 'purged' AND purged_at IS NOT NULL AND restored_at IS NULL)
  )
);
CREATE UNIQUE INDEX resource_trash_memberships_one_active_resource
  ON public.resource_trash_memberships(org_id, resource_type, resource_id)
  WHERE state IN ('active', 'restoring', 'purging');
CREATE INDEX resource_trash_memberships_operation_tree_idx
  ON public.resource_trash_memberships(org_id, operation_id, parent_membership_id, created_at);

ALTER TABLE public.clients
  ADD CONSTRAINT clients_active_trash_membership_org_fkey
    FOREIGN KEY (org_id, active_trash_membership_id)
    REFERENCES public.resource_trash_memberships(org_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.matters
  ADD CONSTRAINT matters_active_trash_membership_org_fkey
    FOREIGN KEY (org_id, active_trash_membership_id)
    REFERENCES public.resource_trash_memberships(org_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.documents
  ADD CONSTRAINT documents_active_trash_membership_org_fkey
    FOREIGN KEY (org_id, active_trash_membership_id)
    REFERENCES public.resource_trash_memberships(org_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE public.resource_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  resource_type public.trash_resource_type NOT NULL,
  resource_id uuid NOT NULL,
  client_id uuid,
  matter_id uuid,
  document_id uuid,
  scope public.resource_hold_scope NOT NULL DEFAULT 'resource',
  state public.resource_hold_state NOT NULL DEFAULT 'active',
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  authority_reference text,
  created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  released_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  released_at timestamptz,
  CONSTRAINT resource_holds_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT resource_holds_client_org_fkey FOREIGN KEY (org_id, client_id)
    REFERENCES public.clients(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_holds_matter_org_fkey FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_holds_document_org_fkey FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT resource_holds_locator CHECK (
    (resource_type = 'client' AND client_id = resource_id AND matter_id IS NULL AND document_id IS NULL)
    OR (resource_type = 'matter' AND matter_id = resource_id AND client_id IS NULL AND document_id IS NULL)
    OR (resource_type = 'document' AND document_id = resource_id AND client_id IS NULL AND matter_id IS NULL)
  ),
  CONSTRAINT resource_holds_state_timestamps CHECK (
    (state = 'active' AND released_at IS NULL AND released_by IS NULL)
    OR (state = 'released' AND released_at IS NOT NULL)
  )
);
CREATE INDEX resource_holds_active_locator_idx
  ON public.resource_holds(org_id, resource_type, resource_id) WHERE state = 'active';

-- Cross-row validation completes the type-specific composite FKs. It is
-- deferred because future command transactions create a membership and then
-- atomically attach the corresponding resource references.
CREATE FUNCTION public.assert_resource_trash_contract()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  membership public.resource_trash_memberships%ROWTYPE;
  parent public.resource_trash_memberships%ROWTYPE;
  operation public.trash_operations%ROWTYPE;
  actual_client_id uuid;
  actual_matter_id uuid;
  actual_state text;
  actual_reference uuid;
BEGIN
  IF TG_TABLE_NAME = 'resource_trash_memberships' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN NULL;
    END IF;
    -- A deferred constraint trigger receives the row image from the queued
    -- event, not necessarily its final transaction state. Re-read the row so
    -- a valid atomic purge/restore transition is evaluated as a whole.
    SELECT * INTO membership FROM public.resource_trash_memberships
    WHERE id = NEW.id;
    IF membership.id IS NULL THEN
      RETURN NULL;
    END IF;
  ELSE
    RETURN NULL;
  END IF;

  SELECT * INTO operation FROM public.trash_operations
  WHERE org_id = membership.org_id AND id = membership.operation_id;
  IF operation.id IS NULL THEN
    RAISE EXCEPTION 'trash membership operation must remain in the same organisation';
  END IF;
  -- Membership-only writes must not drift from their root operation. This is
  -- deliberately here as well as in the operation trigger because a later
  -- command may transition every member without issuing an operation UPDATE.
  IF (operation.state IN ('trashed', 'restore_blocked', 'purge_scheduled') AND membership.state <> 'active')
     OR (operation.state = 'restoring' AND membership.state <> 'restoring')
     OR (operation.state = 'restored' AND membership.state <> 'restored')
     OR (operation.state IN ('purging', 'purge_failed') AND membership.state <> 'purging')
     OR (operation.state = 'purged' AND membership.state <> 'purged') THEN
    RAISE EXCEPTION 'trash membership lifecycle state must agree with its operation';
  END IF;

  IF membership.cause = 'direct' THEN
    IF membership.resource_type <> operation.root_resource_type
       OR membership.resource_id <> operation.root_resource_id THEN
      RAISE EXCEPTION 'direct trash membership must be the operation root';
    END IF;
  ELSE
    SELECT * INTO parent FROM public.resource_trash_memberships
    WHERE org_id = membership.org_id AND id = membership.parent_membership_id;
    IF parent.id IS NULL OR parent.operation_id <> membership.operation_id THEN
      RAISE EXCEPTION 'inherited trash membership must retain a parent in the same operation';
    END IF;
    IF parent.state <> membership.state THEN
      RAISE EXCEPTION 'inherited trash membership parent must remain active in the same lifecycle state';
    END IF;
    IF membership.resource_type = 'client' THEN
      RAISE EXCEPTION 'client trash membership cannot be inherited';
    ELSIF membership.resource_type = 'matter' THEN
      SELECT client_id INTO actual_client_id FROM public.matters
      WHERE org_id = membership.org_id AND id = membership.resource_id;
      IF parent.resource_type <> 'client' OR parent.resource_id <> actual_client_id THEN
        RAISE EXCEPTION 'inherited matter must have its owning client membership as parent';
      END IF;
    ELSE
      SELECT matter_id INTO actual_matter_id FROM public.documents
      WHERE org_id = membership.org_id AND id = membership.resource_id;
      IF parent.resource_type <> 'matter' OR parent.resource_id <> actual_matter_id THEN
        RAISE EXCEPTION 'inherited document must have its owning matter membership as parent';
      END IF;
    END IF;
  END IF;

  IF membership.resource_type = 'client' THEN
    SELECT record_state::text, active_trash_membership_id INTO actual_state, actual_reference
    FROM public.clients WHERE org_id = membership.org_id AND id = membership.resource_id;
  ELSIF membership.resource_type = 'matter' THEN
    SELECT record_state::text, active_trash_membership_id INTO actual_state, actual_reference
    FROM public.matters WHERE org_id = membership.org_id AND id = membership.resource_id;
  ELSE
    SELECT record_state::text, active_trash_membership_id INTO actual_state, actual_reference
    FROM public.documents WHERE org_id = membership.org_id AND id = membership.resource_id;
  END IF;

  IF membership.state IN ('active', 'restoring', 'purging') THEN
    IF actual_reference IS DISTINCT FROM membership.id THEN
      RAISE EXCEPTION 'active trash membership must be referenced by its resource';
    END IF;
    IF (membership.state IN ('active', 'restoring') AND actual_state <> 'trashed')
       OR (membership.state = 'purging' AND actual_state <> 'purging') THEN
      RAISE EXCEPTION 'resource record state does not match active trash membership state';
    END IF;
  ELSIF membership.state = 'restored' THEN
    IF actual_reference IS NOT NULL OR actual_state <> 'active' THEN
      RAISE EXCEPTION 'restored membership must release an active resource reference';
    END IF;
  ELSIF membership.state = 'purged' THEN
    IF actual_reference IS NOT NULL OR actual_state <> 'purged' THEN
      RAISE EXCEPTION 'purged membership must release an active resource reference';
    END IF;
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION public.assert_resource_trash_operation_memberships()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  operation public.trash_operations%ROWTYPE;
  unexpected_count integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RETURN NULL;
  END IF;
  -- See the matching membership validator: deferred events may be stale by
  -- the time this runs, so validate the committed-in-transaction row shape.
  SELECT * INTO operation FROM public.trash_operations WHERE id = NEW.id;
  IF operation.id IS NULL THEN
    RETURN NULL;
  END IF;
  IF operation.state IN ('trashed', 'restore_blocked', 'purge_scheduled') THEN
    SELECT count(*) INTO unexpected_count FROM public.resource_trash_memberships
    WHERE org_id = operation.org_id AND operation_id = operation.id AND state <> 'active';
  ELSIF operation.state = 'restoring' THEN
    SELECT count(*) INTO unexpected_count FROM public.resource_trash_memberships
    WHERE org_id = operation.org_id AND operation_id = operation.id AND state <> 'restoring';
  ELSIF operation.state = 'restored' THEN
    SELECT count(*) INTO unexpected_count FROM public.resource_trash_memberships
    WHERE org_id = operation.org_id AND operation_id = operation.id AND state <> 'restored';
  ELSIF operation.state IN ('purging', 'purge_failed') THEN
    SELECT count(*) INTO unexpected_count FROM public.resource_trash_memberships
    WHERE org_id = operation.org_id AND operation_id = operation.id AND state <> 'purging';
  ELSE
    SELECT count(*) INTO unexpected_count FROM public.resource_trash_memberships
    WHERE org_id = operation.org_id AND operation_id = operation.id AND state <> 'purged';
  END IF;
  IF unexpected_count <> 0 THEN
    RAISE EXCEPTION 'trash operation and membership lifecycle states must agree';
  END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION public.resource_trash_operation_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'trashed' THEN
      RAISE EXCEPTION 'trash operation must begin in trashed state';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;
  IF OLD.state IN ('restored', 'purged')
     OR (OLD.state = 'trashed' AND NEW.state NOT IN ('restore_blocked', 'restoring', 'purge_scheduled', 'purging'))
     OR (OLD.state = 'restore_blocked' AND NEW.state NOT IN ('trashed', 'restoring', 'purge_scheduled'))
     OR (OLD.state = 'restoring' AND NEW.state NOT IN ('restore_blocked', 'restored'))
     OR (OLD.state = 'purge_scheduled' AND NEW.state NOT IN ('trashed', 'purging'))
     OR (OLD.state = 'purging' AND NEW.state NOT IN ('purge_failed', 'purged'))
     OR (OLD.state = 'purge_failed' AND NEW.state <> 'purging') THEN
    RAISE EXCEPTION 'invalid or terminal trash operation transition';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION public.resource_trash_membership_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'active' THEN
      RAISE EXCEPTION 'trash membership must begin active';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;
  IF OLD.state IN ('restored', 'purged')
     OR (OLD.state = 'active' AND NEW.state NOT IN ('restoring', 'purging'))
     OR (OLD.state = 'restoring' AND NEW.state NOT IN ('active', 'restored'))
     OR (OLD.state = 'purging' AND NEW.state NOT IN ('purged')) THEN
    RAISE EXCEPTION 'invalid or terminal trash membership transition';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION public.resource_trash_protected_state_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- SECURITY DEFINER changes current_user to the function owner. `role`
  -- retains a direct SET ROLE invoker, while the JWT setting covers PostgREST.
  IF (coalesce(current_setting('role', true), '') IN ('anon', 'authenticated', 'service_role')
      OR coalesce(current_setting('request.jwt.claim.role', true), '') IN ('anon', 'authenticated', 'service_role'))
     AND (NEW.record_state IS DISTINCT FROM OLD.record_state
       OR NEW.active_trash_membership_id IS DISTINCT FROM OLD.active_trash_membership_id) THEN
    RAISE EXCEPTION 'trash resource state is writable only through a future service-owned command';
  END IF;
  RETURN NEW;
END $$;

CREATE FUNCTION public.resource_trash_protected_state_insert_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- Do not use current_user here: under SECURITY DEFINER it is postgres.
  IF (coalesce(current_setting('role', true), '') IN ('anon', 'authenticated', 'service_role')
      OR coalesce(current_setting('request.jwt.claim.role', true), '') IN ('anon', 'authenticated', 'service_role'))
     AND (NEW.record_state::text <> 'active' OR NEW.active_trash_membership_id IS NOT NULL) THEN
    RAISE EXCEPTION 'trash resource state is writable only through a future service-owned command';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trash_operations_transition_guard
  BEFORE INSERT OR UPDATE OF state ON public.trash_operations
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_operation_transition_guard();
CREATE TRIGGER resource_trash_memberships_transition_guard
  BEFORE INSERT OR UPDATE OF state ON public.resource_trash_memberships
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_membership_transition_guard();
CREATE TRIGGER clients_trash_protected_state_guard
  BEFORE UPDATE OF record_state, active_trash_membership_id ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_guard();
CREATE TRIGGER clients_trash_protected_state_insert_guard
  BEFORE INSERT ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_insert_guard();
CREATE TRIGGER matters_trash_protected_state_guard
  BEFORE UPDATE OF record_state, active_trash_membership_id ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_guard();
CREATE TRIGGER matters_trash_protected_state_insert_guard
  BEFORE INSERT ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_insert_guard();
CREATE TRIGGER documents_trash_protected_state_guard
  BEFORE UPDATE OF record_state, active_trash_membership_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_guard();
CREATE TRIGGER documents_trash_protected_state_insert_guard
  BEFORE INSERT ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.resource_trash_protected_state_insert_guard();

CREATE CONSTRAINT TRIGGER resource_trash_memberships_contract
  AFTER INSERT OR UPDATE OR DELETE ON public.resource_trash_memberships
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION public.assert_resource_trash_contract();
CREATE CONSTRAINT TRIGGER trash_operations_membership_contract
  AFTER INSERT OR UPDATE OR DELETE ON public.trash_operations
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION public.assert_resource_trash_operation_memberships();

-- The resource-side triggers arrange for a membership write to be validated
-- after either end of the deferred relationship changes.
CREATE FUNCTION public.assert_resource_trash_resource_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE membership public.resource_trash_memberships%ROWTYPE;
BEGIN
  IF NEW.active_trash_membership_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT * INTO membership FROM public.resource_trash_memberships
  WHERE org_id = NEW.org_id AND id = NEW.active_trash_membership_id;
  IF membership.id IS NULL THEN
    RAISE EXCEPTION 'resource trash membership reference must remain in the same organisation';
  END IF;
  IF (TG_TABLE_NAME = 'clients' AND (membership.resource_type <> 'client' OR membership.resource_id <> NEW.id))
     OR (TG_TABLE_NAME = 'matters' AND (membership.resource_type <> 'matter' OR membership.resource_id <> NEW.id))
     OR (TG_TABLE_NAME = 'documents' AND (membership.resource_type <> 'document' OR membership.resource_id <> NEW.id)) THEN
    RAISE EXCEPTION 'resource active trash membership must locate that exact resource';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER clients_trash_reference_contract
  AFTER INSERT OR UPDATE OF org_id, record_state, active_trash_membership_id ON public.clients
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_resource_trash_resource_reference();
CREATE CONSTRAINT TRIGGER matters_trash_reference_contract
  AFTER INSERT OR UPDATE OF org_id, record_state, active_trash_membership_id ON public.matters
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_resource_trash_resource_reference();
CREATE CONSTRAINT TRIGGER documents_trash_reference_contract
  AFTER INSERT OR UPDATE OF org_id, record_state, active_trash_membership_id ON public.documents
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.assert_resource_trash_resource_reference();

ALTER TABLE public.organisation_retention_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organisation_retention_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.trash_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_operations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.resource_trash_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_trash_memberships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.resource_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.resource_holds FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.organisation_retention_settings, public.trash_operations,
  public.resource_trash_memberships, public.resource_holds
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.assert_resource_trash_contract(),
  public.assert_resource_trash_operation_memberships(),
  public.resource_trash_operation_transition_guard(),
  public.resource_trash_membership_transition_guard(),
  public.resource_trash_protected_state_guard(),
  public.resource_trash_protected_state_insert_guard(),
  public.assert_resource_trash_resource_reference()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.organisation_retention_settings IS
  'Service-private prospective trash retention policy. Manual purge only is the initial required default.';
COMMENT ON TABLE public.trash_operations IS
  'Service-private root operation contract for hierarchical Trash. This migration creates no command surface.';
COMMENT ON TABLE public.resource_trash_memberships IS
  'Service-private resource-to-operation tree. Composite lineage and one-active-membership constraints prevent forged hierarchy.';
COMMENT ON TABLE public.resource_holds IS
  'Service-private legal-hold/blocker interface. Holds will block a later purge command but do not block trash or restore.';

COMMIT;
