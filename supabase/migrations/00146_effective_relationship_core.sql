-- Canonical effective document relationships for the Matter Timeline.
-- Legacy document_links remains non-canonical and is deliberately neither
-- backfilled nor consulted by this contract.
BEGIN;

CREATE TYPE public.document_relationship_type AS ENUM (
  'responds_to',
  'issued_pursuant_to',
  'arises_from',
  'challenges',
  'decides',
  'modifies',
  'supersedes',
  'remands',
  'gives_effect_to',
  'refers_to',
  'other'
);

CREATE TYPE public.document_relationship_verification AS ENUM (
  'human', 'policy_confirmed', 'provisional'
);

CREATE TYPE public.document_relationship_lifecycle AS ENUM (
  'active', 'stale', 'suspended', 'archived'
);

CREATE TYPE public.document_relationship_decision_action AS ENUM (
  'activate', 'accept', 'correct', 'reject', 'clear', 'archive'
);

CREATE TABLE public.document_relationship_catalogue (
  relationship_type public.document_relationship_type NOT NULL,
  catalogue_version integer NOT NULL CHECK (catalogue_version >= 1),
  canonical_phrase text NOT NULL CHECK (
    char_length(canonical_phrase) BETWEEN 2 AND 80
    AND canonical_phrase !~ '[[:cntrl:]]'
  ),
  progression_phrase text NOT NULL CHECK (
    char_length(progression_phrase) BETWEEN 2 AND 80
    AND progression_phrase !~ '[[:cntrl:]]'
  ),
  timeline_visible boolean NOT NULL,
  acyclic boolean NOT NULL,
  allowed_source_classes text[] NOT NULL CHECK (
    cardinality(allowed_source_classes) > 0
    AND allowed_source_classes <@ ARRAY['proceeding', 'supporting']::text[]
  ),
  allowed_target_classes text[] NOT NULL CHECK (
    cardinality(allowed_target_classes) > 0
    AND allowed_target_classes <@ ARRAY['proceeding', 'supporting']::text[]
  ),
  reject_same_type_inverse boolean NOT NULL,
  display_priority smallint NOT NULL CHECK (display_priority BETWEEN 1 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_type, catalogue_version),
  CONSTRAINT document_relationship_catalogue_timeline_acyclic
    CHECK (NOT timeline_visible OR acyclic)
);

INSERT INTO public.document_relationship_catalogue(
  relationship_type, catalogue_version, canonical_phrase, progression_phrase,
  timeline_visible, acyclic, allowed_source_classes, allowed_target_classes,
  reject_same_type_inverse, display_priority
) VALUES
  ('responds_to',1,'responds to','answered by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,10),
  ('issued_pursuant_to',1,'is issued pursuant to','results in',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,20),
  ('arises_from',1,'arises from','gives rise to',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,30),
  ('challenges',1,'challenges','is challenged by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,40),
  ('decides',1,'decides','is decided by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,50),
  ('modifies',1,'modifies','is modified by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,60),
  ('supersedes',1,'supersedes','is superseded by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,70),
  ('remands',1,'remands','is remanded by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,80),
  ('gives_effect_to',1,'gives effect to','is given effect by',true,true,ARRAY['proceeding'],ARRAY['proceeding'],true,90),
  ('refers_to',1,'refers to','is referred to by',false,false,ARRAY['proceeding'],ARRAY['proceeding'],false,95),
  ('other',1,'is related to','has related progression',false,false,ARRAY['proceeding'],ARRAY['proceeding'],false,100);

CREATE TABLE public.document_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  source_document_id uuid NOT NULL,
  target_document_id uuid NOT NULL,
  relationship_type public.document_relationship_type NOT NULL,
  catalogue_version integer NOT NULL,
  verification public.document_relationship_verification NOT NULL,
  provenance text NOT NULL CHECK (provenance IN ('manual', 'candidate', 'deterministic_rule')),
  lifecycle_state public.document_relationship_lifecycle NOT NULL DEFAULT 'active',
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  activated_at timestamptz NOT NULL DEFAULT now(),
  activated_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  archived_at timestamptz,
  archived_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  archive_reason text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_relationships_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_relationships_matter_org_fkey
    FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_relationships_source_org_fkey
    FOREIGN KEY (org_id, source_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_relationships_target_org_fkey
    FOREIGN KEY (org_id, target_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_relationships_catalogue_fkey
    FOREIGN KEY (relationship_type, catalogue_version)
    REFERENCES public.document_relationship_catalogue(relationship_type, catalogue_version) ON DELETE RESTRICT,
  CONSTRAINT document_relationships_not_self CHECK (source_document_id <> target_document_id),
  CONSTRAINT document_relationships_archive_shape CHECK (
    (lifecycle_state <> 'archived' AND archived_at IS NULL AND archived_by IS NULL AND archive_reason IS NULL)
    OR (lifecycle_state = 'archived' AND archived_at IS NOT NULL AND archived_by IS NOT NULL
      AND archive_reason IS NOT NULL AND char_length(archive_reason) BETWEEN 1 AND 500
      AND archive_reason !~ '[[:cntrl:]]')
  )
);

CREATE UNIQUE INDEX document_relationships_one_active_type
  ON public.document_relationships(org_id, source_document_id, target_document_id, relationship_type)
  WHERE lifecycle_state = 'active';
CREATE INDEX document_relationships_active_matter_source_idx
  ON public.document_relationships(org_id, matter_id, source_document_id, target_document_id)
  WHERE lifecycle_state = 'active';
CREATE INDEX document_relationships_active_matter_target_idx
  ON public.document_relationships(org_id, matter_id, target_document_id, source_document_id)
  WHERE lifecycle_state = 'active';

CREATE TABLE public.document_relationship_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  org_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  relationship_id uuid NOT NULL,
  source_document_id uuid NOT NULL,
  target_document_id uuid NOT NULL,
  relationship_type public.document_relationship_type NOT NULL,
  action public.document_relationship_decision_action NOT NULL,
  from_lifecycle public.document_relationship_lifecycle,
  to_lifecycle public.document_relationship_lifecycle NOT NULL,
  reason text,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  resulting_revision bigint NOT NULL CHECK (resulting_revision >= 1),
  idempotency_key uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_relationship_decisions_relationship_org_fkey
    FOREIGN KEY (org_id, relationship_id)
    REFERENCES public.document_relationships(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_relationship_decisions_matter_org_fkey
    FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_relationship_decisions_reason_safe CHECK (
    reason IS NULL OR (char_length(reason) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]')
  )
);
CREATE INDEX document_relationship_decisions_relationship_history_idx
  ON public.document_relationship_decisions(org_id, relationship_id, decision_sequence);

CREATE TABLE public.document_relationship_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('activate', 'archive')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  relationship_id uuid NOT NULL,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  result_code text NOT NULL CHECK (result_code = 'ok'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_relationship_command_receipts_relationship_org_fkey
    FOREIGN KEY (org_id, relationship_id)
    REFERENCES public.document_relationships(org_id, id) ON DELETE RESTRICT
);
CREATE INDEX document_relationship_command_receipts_actor_org_created_idx
  ON public.document_relationship_command_receipts(actor_user_id, org_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.relationship_catalogue_prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'Relationship catalogue rows are immutable; add a new version';
END $$;
CREATE TRIGGER document_relationship_catalogue_no_mutation
  BEFORE UPDATE OR DELETE ON public.document_relationship_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.relationship_catalogue_prevent_mutation();

CREATE OR REPLACE FUNCTION public.relationship_decisions_prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'Relationship decisions are append-only';
END $$;
CREATE TRIGGER document_relationship_decisions_no_mutation
  BEFORE UPDATE OR DELETE ON public.document_relationship_decisions
  FOR EACH ROW EXECUTE FUNCTION public.relationship_decisions_prevent_mutation();

CREATE OR REPLACE FUNCTION public.enforce_document_relationship()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_catalogue public.document_relationship_catalogue%ROWTYPE;
  v_source public.documents%ROWTYPE;
  v_target public.documents%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' AND (
    NEW.org_id IS DISTINCT FROM OLD.org_id
    OR NEW.matter_id IS DISTINCT FROM OLD.matter_id
    OR NEW.source_document_id IS DISTINCT FROM OLD.source_document_id
    OR NEW.target_document_id IS DISTINCT FROM OLD.target_document_id
    OR NEW.relationship_type IS DISTINCT FROM OLD.relationship_type
    OR NEW.catalogue_version IS DISTINCT FROM OLD.catalogue_version
    OR NEW.verification IS DISTINCT FROM OLD.verification
    OR NEW.provenance IS DISTINCT FROM OLD.provenance
    OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
    OR NEW.activated_by IS DISTINCT FROM OLD.activated_by
  ) THEN
    RAISE EXCEPTION 'Effective relationship identity and provenance are immutable' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_catalogue
  FROM public.document_relationship_catalogue AS catalogue
  WHERE catalogue.relationship_type = NEW.relationship_type
    AND catalogue.catalogue_version = NEW.catalogue_version;
  IF v_catalogue.relationship_type IS NULL THEN
    RAISE EXCEPTION 'Relationship catalogue version is unavailable' USING ERRCODE = '23514';
  END IF;

  IF NEW.lifecycle_state = 'active' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(NEW.org_id::text || ':' || NEW.matter_id::text, 146)
    );

    SELECT * INTO v_source FROM public.documents AS document
    WHERE document.id = NEW.source_document_id
      AND document.org_id = NEW.org_id
      AND document.matter_id = NEW.matter_id;
    SELECT * INTO v_target FROM public.documents AS document
    WHERE document.id = NEW.target_document_id
      AND document.org_id = NEW.org_id
      AND document.matter_id = NEW.matter_id;
    IF v_source.id IS NULL OR v_target.id IS NULL
       OR v_source.record_state <> 'active' OR v_source.deleted_at IS NOT NULL
       OR v_target.record_state <> 'active' OR v_target.deleted_at IS NOT NULL
       OR NOT coalesce(v_source.document_class, '') = ANY(v_catalogue.allowed_source_classes)
       OR NOT coalesce(v_target.document_class, '') = ANY(v_catalogue.allowed_target_classes)
       OR NOT EXISTS (
         SELECT 1
         FROM public.matters AS matter
         JOIN public.clients AS client
           ON client.id = matter.client_id AND client.org_id = matter.org_id
         WHERE matter.id = NEW.matter_id AND matter.org_id = NEW.org_id
           AND matter.record_state = 'active' AND matter.deleted_at IS NULL
           AND matter.work_state <> 'closed'
           AND client.record_state = 'active' AND client.deleted_at IS NULL
       ) THEN
      RAISE EXCEPTION 'Effective relationship endpoints are unavailable' USING ERRCODE = '23514';
    END IF;

    IF v_catalogue.reject_same_type_inverse AND EXISTS (
      SELECT 1 FROM public.document_relationships AS inverse
      WHERE inverse.org_id = NEW.org_id
        AND inverse.matter_id = NEW.matter_id
        AND inverse.source_document_id = NEW.target_document_id
        AND inverse.target_document_id = NEW.source_document_id
        AND inverse.relationship_type = NEW.relationship_type
        AND inverse.lifecycle_state = 'active'
        AND inverse.id <> NEW.id
    ) THEN
      RAISE EXCEPTION 'Impossible inverse relationship' USING ERRCODE = '23514';
    END IF;

    IF v_catalogue.acyclic AND EXISTS (
      WITH RECURSIVE reachable(document_id) AS (
        SELECT relationship.target_document_id
        FROM public.document_relationships AS relationship
        JOIN public.document_relationship_catalogue AS catalogue
          ON catalogue.relationship_type = relationship.relationship_type
         AND catalogue.catalogue_version = relationship.catalogue_version
         AND catalogue.acyclic
        WHERE relationship.org_id = NEW.org_id
          AND relationship.matter_id = NEW.matter_id
          AND relationship.lifecycle_state = 'active'
          AND relationship.source_document_id = NEW.target_document_id
          AND relationship.id <> NEW.id
        UNION
        SELECT relationship.target_document_id
        FROM reachable
        JOIN public.document_relationships AS relationship
          ON relationship.source_document_id = reachable.document_id
         AND relationship.org_id = NEW.org_id
         AND relationship.matter_id = NEW.matter_id
         AND relationship.lifecycle_state = 'active'
        JOIN public.document_relationship_catalogue AS catalogue
          ON catalogue.relationship_type = relationship.relationship_type
         AND catalogue.catalogue_version = relationship.catalogue_version
         AND catalogue.acyclic
        WHERE relationship.id <> NEW.id
      )
      SELECT 1 FROM reachable WHERE document_id = NEW.source_document_id
    ) THEN
      RAISE EXCEPTION 'Timeline-visible relationships must remain acyclic' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_relationships_enforce_contract
  BEFORE INSERT OR UPDATE ON public.document_relationships
  FOR EACH ROW EXECUTE FUNCTION public.enforce_document_relationship();

CREATE OR REPLACE FUNCTION public.enforce_document_relationship_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.document_relationships AS relationship
    WHERE relationship.id = NEW.relationship_id
      AND relationship.org_id = NEW.org_id
      AND relationship.matter_id = NEW.matter_id
      AND relationship.source_document_id = NEW.source_document_id
      AND relationship.target_document_id = NEW.target_document_id
      AND relationship.relationship_type = NEW.relationship_type
      AND relationship.revision = NEW.resulting_revision
  ) THEN
    RAISE EXCEPTION 'Relationship decision lineage mismatch' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_relationship_decisions_enforce_lineage
  BEFORE INSERT ON public.document_relationship_decisions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_document_relationship_decision();

-- Relationship management follows the current Associate content-mutation
-- baseline. Suspended membership produces no capabilities and Viewer remains
-- read-only.
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
      'trash.retention.manage','document.view','document.intake.create',
      'document.record.create','document.intake.assign','document.intake.discard',
      'document.version.attach','document.version.replace','document.reprocess',
      'document.metadata.decide','trash.document','trash.hierarchy','relationship.manage'
    ]::text[]
    WHEN p_role = 'admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','trash.retention.manage',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','trash.hierarchy','relationship.manage'
    ]::text[]
    WHEN p_role = 'associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','relationship.manage'
    ]::text[]
    ELSE ARRAY['team.view','document.view']::text[]
  END
$$;

CREATE OR REPLACE FUNCTION public.get_my_organisation_context()
RETURNS TABLE (
  membership_id uuid, org_id uuid, role public.org_member_role,
  is_owner boolean, state public.organisation_membership_state,
  capability_version integer, capabilities text[], revision bigint
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT membership.id, membership.org_id, membership.role,
    organisation.owner_membership_id = membership.id, membership.state, 9,
    public.organisation_member_capabilities(
      membership.role,
      organisation.owner_membership_id = membership.id,
      membership.state
    ), membership.revision
  FROM public.organisation_memberships AS membership
  JOIN public.organisations AS organisation ON organisation.id = membership.org_id
  WHERE membership.user_id = auth.uid()
    AND membership.state IN ('active', 'suspended')
$$;

CREATE OR REPLACE FUNCTION public.document_relationship_reason_is_safe(
  p_reason text,
  p_required boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT CASE
    WHEN p_reason IS NULL THEN NOT p_required
    ELSE char_length(p_reason) BETWEEN 1 AND 500 AND p_reason !~ '[[:cntrl:]]'
  END
$$;

CREATE OR REPLACE FUNCTION public.activate_document_relationship(
  p_matter_id uuid,
  p_source_document_id uuid,
  p_target_document_id uuid,
  p_relationship_type public.document_relationship_type,
  p_expected_source_revision bigint,
  p_expected_target_revision bigint,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, relationship_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_reason text := nullif(btrim(p_reason), '');
  v_fingerprint text;
  v_receipt public.document_relationship_command_receipts%ROWTYPE;
  v_matter public.matters%ROWTYPE;
  v_source public.documents%ROWTYPE;
  v_target public.documents%ROWTYPE;
  v_catalogue public.document_relationship_catalogue%ROWTYPE;
  v_relationship public.document_relationships%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_matter_id IS NULL OR p_source_document_id IS NULL
     OR p_target_document_id IS NULL OR p_relationship_type IS NULL
     OR p_expected_source_revision IS NULL OR p_expected_source_revision < 1
     OR p_expected_target_revision IS NULL OR p_expected_target_revision < 1
     OR p_idempotency_key IS NULL
     OR NOT public.document_relationship_reason_is_safe(v_reason, false) THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF p_source_document_id = p_target_document_id THEN
    RETURN QUERY SELECT 'self_relationship', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 146)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor
      AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation
  WHERE organisation.id = v_membership.org_id;
  IF NOT ('relationship.manage' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false), v_membership.state
  ))) THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','activate','matter_id',p_matter_id,
    'source_document_id',p_source_document_id,'target_document_id',p_target_document_id,
    'relationship_type',p_relationship_type::text,
    'expected_source_revision',p_expected_source_revision,
    'expected_target_revision',p_expected_target_revision,'reason',v_reason
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt
  FROM public.document_relationship_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_membership.org_id
       OR v_receipt.command <> 'activate' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::uuid, NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code, v_receipt.relationship_id,
        v_receipt.result_revision, true;
    END IF;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_membership.org_id::text || ':' || p_matter_id::text, 146)
  );
  SELECT matter.* INTO v_matter
  FROM public.matters AS matter
  JOIN public.clients AS client
    ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR UPDATE OF matter, client;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  PERFORM 1 FROM public.documents AS document
  WHERE document.id IN (p_source_document_id, p_target_document_id)
  ORDER BY document.id FOR UPDATE;
  SELECT * INTO v_source FROM public.documents AS document
  WHERE document.id = p_source_document_id
    AND document.org_id = v_membership.org_id AND document.matter_id = p_matter_id;
  SELECT * INTO v_target FROM public.documents AS document
  WHERE document.id = p_target_document_id
    AND document.org_id = v_membership.org_id AND document.matter_id = p_matter_id;
  IF v_source.id IS NULL OR v_target.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_source.record_state <> 'active' OR v_source.deleted_at IS NOT NULL
     OR v_target.record_state <> 'active' OR v_target.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'endpoint_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_source.document_class IS DISTINCT FROM 'proceeding'
     OR v_target.document_class IS DISTINCT FROM 'proceeding' THEN
    RETURN QUERY SELECT 'invalid_endpoint_class', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_source.lifecycle_revision <> p_expected_source_revision
     OR v_target.lifecycle_revision <> p_expected_target_revision THEN
    RETURN QUERY SELECT 'conflict', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  SELECT * INTO v_catalogue
  FROM public.document_relationship_catalogue AS catalogue
  WHERE catalogue.relationship_type = p_relationship_type
  ORDER BY catalogue.catalogue_version DESC
  LIMIT 1;
  IF v_catalogue.relationship_type IS NULL
     OR NOT coalesce(v_source.document_class, '') = ANY(v_catalogue.allowed_source_classes)
     OR NOT coalesce(v_target.document_class, '') = ANY(v_catalogue.allowed_target_classes) THEN
    RETURN QUERY SELECT 'invalid_relationship_type', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  SELECT * INTO v_relationship
  FROM public.document_relationships AS relationship
  WHERE relationship.org_id = v_membership.org_id
    AND relationship.source_document_id = p_source_document_id
    AND relationship.target_document_id = p_target_document_id
    AND relationship.relationship_type = p_relationship_type
    AND relationship.lifecycle_state = 'active'
  FOR UPDATE;
  IF v_relationship.id IS NOT NULL THEN
    RETURN QUERY SELECT 'duplicate_active', v_relationship.id, v_relationship.revision, false;
    RETURN;
  END IF;
  IF v_catalogue.reject_same_type_inverse AND EXISTS (
    SELECT 1 FROM public.document_relationships AS inverse
    WHERE inverse.org_id = v_membership.org_id AND inverse.matter_id = p_matter_id
      AND inverse.source_document_id = p_target_document_id
      AND inverse.target_document_id = p_source_document_id
      AND inverse.relationship_type = p_relationship_type
      AND inverse.lifecycle_state = 'active'
  ) THEN
    RETURN QUERY SELECT 'inverse_conflict', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_catalogue.acyclic AND EXISTS (
    WITH RECURSIVE reachable(document_id) AS (
      SELECT relationship.target_document_id
      FROM public.document_relationships AS relationship
      JOIN public.document_relationship_catalogue AS catalogue
        ON catalogue.relationship_type = relationship.relationship_type
       AND catalogue.catalogue_version = relationship.catalogue_version
       AND catalogue.acyclic
      WHERE relationship.org_id = v_membership.org_id
        AND relationship.matter_id = p_matter_id
        AND relationship.lifecycle_state = 'active'
        AND relationship.source_document_id = p_target_document_id
      UNION
      SELECT relationship.target_document_id
      FROM reachable
      JOIN public.document_relationships AS relationship
        ON relationship.source_document_id = reachable.document_id
       AND relationship.org_id = v_membership.org_id
       AND relationship.matter_id = p_matter_id
       AND relationship.lifecycle_state = 'active'
      JOIN public.document_relationship_catalogue AS catalogue
        ON catalogue.relationship_type = relationship.relationship_type
       AND catalogue.catalogue_version = relationship.catalogue_version
       AND catalogue.acyclic
    )
    SELECT 1 FROM reachable WHERE document_id = p_source_document_id
  ) THEN
    RETURN QUERY SELECT 'cycle_detected', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.document_relationships(
      org_id,matter_id,source_document_id,target_document_id,relationship_type,
      catalogue_version,verification,provenance,lifecycle_state,activated_by
    ) VALUES (
      v_membership.org_id,p_matter_id,p_source_document_id,p_target_document_id,
      p_relationship_type,v_catalogue.catalogue_version,'human','manual','active',v_actor
    ) RETURNING * INTO v_relationship;
    INSERT INTO public.document_relationship_decisions(
      org_id,matter_id,relationship_id,source_document_id,target_document_id,
      relationship_type,action,from_lifecycle,to_lifecycle,reason,actor_user_id,
      resulting_revision,idempotency_key
    ) VALUES (
      v_membership.org_id,p_matter_id,v_relationship.id,p_source_document_id,
      p_target_document_id,p_relationship_type,'activate',NULL,'active',v_reason,
      v_actor,v_relationship.revision,p_idempotency_key
    );
    PERFORM public.append_activity_event(
      v_membership.org_id,'document.link_changed',1::smallint,'user',v_actor,'Member',
      'document',p_source_document_id,v_matter.client_id,p_matter_id,'Document',
      'Document relationship activated',
      jsonb_build_object('link_action','activate.' || p_relationship_type::text),
      'document',p_target_document_id,NULL,p_idempotency_key,NULL,
      'relationship.activate.' || p_idempotency_key::text,now()
    );
    INSERT INTO public.document_relationship_command_receipts(
      org_id,actor_user_id,idempotency_key,command,request_fingerprint,
      relationship_id,result_revision,result_code
    ) VALUES (
      v_membership.org_id,v_actor,p_idempotency_key,'activate',v_fingerprint,
      v_relationship.id,v_relationship.revision,'ok'
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT 'duplicate_active', NULL::uuid, NULL::bigint, false;
      RETURN;
    WHEN check_violation OR foreign_key_violation THEN
      RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
      RETURN;
    WHEN others THEN
      RETURN QUERY SELECT 'write_failed', NULL::uuid, NULL::bigint, false;
      RETURN;
  END;
  RETURN QUERY SELECT 'ok', v_relationship.id, v_relationship.revision, false;
END $$;

CREATE OR REPLACE FUNCTION public.archive_document_relationship(
  p_relationship_id uuid,
  p_expected_revision bigint,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, relationship_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_reason text := nullif(btrim(p_reason), '');
  v_fingerprint text;
  v_receipt public.document_relationship_command_receipts%ROWTYPE;
  v_relationship public.document_relationships%ROWTYPE;
  v_matter public.matters%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_relationship_id IS NULL OR p_expected_revision IS NULL
     OR p_expected_revision < 1 OR p_idempotency_key IS NULL
     OR NOT public.document_relationship_reason_is_safe(v_reason, true) THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 146)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor
      AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation WHERE organisation.id = v_membership.org_id;
  IF NOT ('relationship.manage' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false), v_membership.state
  ))) THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','archive','relationship_id',p_relationship_id,
    'expected_revision',p_expected_revision,'reason',v_reason
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.document_relationship_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_membership.org_id
       OR v_receipt.command <> 'archive' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::uuid, NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code,v_receipt.relationship_id,
        v_receipt.result_revision,true;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_relationship FROM public.document_relationships AS relationship
  WHERE relationship.id = p_relationship_id AND relationship.org_id = v_membership.org_id;
  IF v_relationship.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_membership.org_id::text || ':' || v_relationship.matter_id::text, 146)
  );
  SELECT * INTO v_relationship FROM public.document_relationships AS relationship
  WHERE relationship.id = p_relationship_id AND relationship.org_id = v_membership.org_id
  FOR UPDATE;
  SELECT matter.* INTO v_matter
  FROM public.matters AS matter
  JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = v_relationship.matter_id AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR UPDATE OF matter, client;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  PERFORM 1 FROM public.documents AS document
  WHERE document.id IN (v_relationship.source_document_id,v_relationship.target_document_id)
  ORDER BY document.id FOR UPDATE;
  IF NOT EXISTS (
    SELECT 1 FROM public.documents AS source
    JOIN public.documents AS target
      ON target.id = v_relationship.target_document_id
     AND target.org_id = source.org_id AND target.matter_id = source.matter_id
    WHERE source.id = v_relationship.source_document_id
      AND source.org_id = v_membership.org_id AND source.matter_id = v_relationship.matter_id
      AND source.record_state = 'active' AND source.deleted_at IS NULL
      AND source.document_class = 'proceeding'
      AND target.record_state = 'active' AND target.deleted_at IS NULL
      AND target.document_class = 'proceeding'
  ) THEN
    RETURN QUERY SELECT 'endpoint_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_relationship.lifecycle_state <> 'active' THEN
    RETURN QUERY SELECT 'relationship_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  IF v_relationship.revision <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict', v_relationship.id, v_relationship.revision, false;
    RETURN;
  END IF;

  BEGIN
    UPDATE public.document_relationships AS relationship
    SET lifecycle_state = 'archived', revision = relationship.revision + 1,
      archived_at = now(), archived_by = v_actor, archive_reason = v_reason,
      updated_at = now()
    WHERE relationship.id = v_relationship.id
    RETURNING * INTO v_relationship;
    INSERT INTO public.document_relationship_decisions(
      org_id,matter_id,relationship_id,source_document_id,target_document_id,
      relationship_type,action,from_lifecycle,to_lifecycle,reason,actor_user_id,
      resulting_revision,idempotency_key
    ) VALUES (
      v_relationship.org_id,v_relationship.matter_id,v_relationship.id,
      v_relationship.source_document_id,v_relationship.target_document_id,
      v_relationship.relationship_type,'archive','active','archived',v_reason,
      v_actor,v_relationship.revision,p_idempotency_key
    );
    PERFORM public.append_activity_event(
      v_relationship.org_id,'document.link_changed',1::smallint,'user',v_actor,'Member',
      'document',v_relationship.source_document_id,v_matter.client_id,v_matter.id,'Document',
      'Document relationship archived',
      jsonb_build_object('link_action','archive.' || v_relationship.relationship_type::text),
      'document',v_relationship.target_document_id,NULL,p_idempotency_key,NULL,
      'relationship.archive.' || p_idempotency_key::text,now()
    );
    INSERT INTO public.document_relationship_command_receipts(
      org_id,actor_user_id,idempotency_key,command,request_fingerprint,
      relationship_id,result_revision,result_code
    ) VALUES (
      v_relationship.org_id,v_actor,p_idempotency_key,'archive',v_fingerprint,
      v_relationship.id,v_relationship.revision,'ok'
    );
  EXCEPTION WHEN others THEN
    RETURN QUERY SELECT 'write_failed', NULL::uuid, NULL::bigint, false;
    RETURN;
  END;
  RETURN QUERY SELECT 'ok',v_relationship.id,v_relationship.revision,false;
END $$;

CREATE OR REPLACE FUNCTION public.read_matter_timeline_relationships(
  p_matter_id uuid,
  p_selected_document_id uuid DEFAULT NULL
)
RETURNS TABLE(
  outcome text,
  relationships jsonb,
  source_revision text,
  fetched_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org uuid;
  v_member_count integer;
BEGIN
  IF p_matter_id IS NULL THEN
    RETURN QUERY SELECT 'unavailable','[]'::jsonb,NULL::text,clock_timestamp();
    RETURN;
  END IF;
  SELECT count(*)::integer,min(authorised.org_id::text)::uuid
  INTO v_member_count,v_org
  FROM (
    SELECT membership.org_id
    FROM public.current_active_tenant_membership() AS membership
    JOIN public.organisations AS organisation ON organisation.id = membership.org_id
    WHERE 'document.view' = ANY(public.organisation_member_capabilities(
      membership.role,
      organisation.owner_membership_id = membership.membership_id,
      'active'::public.organisation_membership_state
    ))
  ) AS authorised;
  IF v_member_count <> 1 OR NOT EXISTS (
    SELECT 1 FROM public.matters AS matter
    JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
    WHERE matter.id = p_matter_id AND matter.org_id = v_org
      AND matter.record_state = 'active' AND matter.deleted_at IS NULL
      AND client.record_state = 'active' AND client.deleted_at IS NULL
  ) OR (p_selected_document_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.documents AS document
    WHERE document.id = p_selected_document_id AND document.org_id = v_org
      AND document.matter_id = p_matter_id AND document.document_class = 'proceeding'
      AND document.record_state = 'active' AND document.deleted_at IS NULL
  )) THEN
    RETURN QUERY SELECT 'unavailable','[]'::jsonb,NULL::text,clock_timestamp();
    RETURN;
  END IF;

  RETURN QUERY
  WITH projected AS (
    SELECT
      relationship.id,relationship.revision,relationship.source_document_id,
      relationship.target_document_id,relationship.relationship_type,
      relationship.verification,catalogue.canonical_phrase,
      catalogue.progression_phrase,catalogue.display_priority,
      source.display_title AS source_title,target.display_title AS target_title
    FROM public.document_relationships AS relationship
    JOIN public.document_relationship_catalogue AS catalogue
      ON catalogue.relationship_type = relationship.relationship_type
     AND catalogue.catalogue_version = relationship.catalogue_version
     AND catalogue.timeline_visible
    JOIN public.documents AS source
      ON source.id = relationship.source_document_id AND source.org_id = relationship.org_id
     AND source.matter_id = relationship.matter_id AND source.document_class = 'proceeding'
     AND source.record_state = 'active' AND source.deleted_at IS NULL
    JOIN public.documents AS target
      ON target.id = relationship.target_document_id AND target.org_id = relationship.org_id
     AND target.matter_id = relationship.matter_id AND target.document_class = 'proceeding'
     AND target.record_state = 'active' AND target.deleted_at IS NULL
    WHERE relationship.org_id = v_org AND relationship.matter_id = p_matter_id
      AND relationship.lifecycle_state = 'active'
      AND (p_selected_document_id IS NULL OR p_selected_document_id IN (
        relationship.source_document_id,relationship.target_document_id
      ))
  )
  SELECT 'ok',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',projected.id,
      'revision',projected.revision,
      'canonicalSourceDocumentId',projected.source_document_id,
      'canonicalTargetDocumentId',projected.target_document_id,
      'displayFromDocumentId',projected.target_document_id,
      'displayToDocumentId',projected.source_document_id,
      'relationshipType',projected.relationship_type,
      'canonicalPhrase',projected.canonical_phrase,
      'progressionPhrase',projected.progression_phrase,
      'verification',projected.verification,
      'canonicalSourceTitle',coalesce(nullif(projected.source_title,''),'Untitled proceeding'),
      'canonicalTargetTitle',coalesce(nullif(projected.target_title,''),'Untitled proceeding')
    ) ORDER BY projected.display_priority,projected.relationship_type,projected.id)
    FROM projected
  ),'[]'::jsonb),md5(coalesce((
    SELECT string_agg(concat_ws(':',projected.id,projected.revision,
      projected.relationship_type,projected.canonical_phrase,projected.progression_phrase),'|'
      ORDER BY projected.id)
    FROM projected
  ),'')),clock_timestamp();
END $$;

ALTER TABLE public.document_relationship_catalogue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationship_catalogue FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationships FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationship_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationship_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationship_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_relationship_command_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.document_relationship_catalogue,public.document_relationships,
  public.document_relationship_decisions,public.document_relationship_command_receipts
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.relationship_catalogue_prevent_mutation(),
  public.relationship_decisions_prevent_mutation(),public.enforce_document_relationship(),
  public.enforce_document_relationship_decision(),
  public.document_relationship_reason_is_safe(text,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.activate_document_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,text,uuid),
  public.archive_document_relationship(uuid,bigint,text,uuid),
  public.read_matter_timeline_relationships(uuid,uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.activate_document_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,text,uuid),
  public.archive_document_relationship(uuid,bigint,text,uuid),
  public.read_matter_timeline_relationships(uuid,uuid)
  TO authenticated;

COMMENT ON TABLE public.document_relationships IS
  'Canonical effective directed document relationships. Legacy document_links is non-canonical and is never inferred or backfilled here.';
COMMENT ON FUNCTION public.activate_document_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,text,uuid) IS
  'Authenticated manual activation with exact membership, endpoint revisions, matter serialization, catalogue inverse/cycle guards, append-only decision, and canonical Activity/outbox.';
COMMENT ON FUNCTION public.archive_document_relationship(uuid,bigint,text,uuid) IS
  'Authenticated reason-required archive with relationship CAS, append-only decision history, and canonical Activity/outbox.';
COMMENT ON FUNCTION public.read_matter_timeline_relationships(uuid,uuid) IS
  'Authorised active Timeline-visible intra-matter effective relationships with catalogue-owned canonical and progression directions; legacy links and candidates are excluded.';

COMMIT;
