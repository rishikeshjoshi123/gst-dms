-- Governed Matter external-identifier authority.
--
-- This foundation deliberately keeps the legacy client/financial-year unique
-- index for D09-T02. It adds an independent, namespaced external-identifier
-- reservation that remains effective while a Matter is in Trash.
BEGIN;

CREATE TYPE public.matter_identifier_kind AS ENUM (
  'proceeding_case_id',
  'notice_reference',
  'order_reference',
  'appeal_reference',
  'court_case_number',
  'other_official_reference'
);

CREATE TYPE public.matter_identifier_role AS ENUM (
  'self_identifier', 'outbound_mention'
);

CREATE TYPE public.matter_identifier_verification_method AS ENUM (
  'human_source', 'unverified_suggestion'
);

CREATE TYPE public.matter_identifier_lifecycle AS ENUM (
  'active', 'revoked'
);

CREATE TYPE public.matter_identifier_decision_action AS ENUM (
  'activate', 'correct', 'revoke'
);

CREATE TABLE public.matter_identifier_normalizer_catalogue (
  normalizer_key text NOT NULL CHECK (normalizer_key ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  normalizer_version integer NOT NULL CHECK (normalizer_version >= 1),
  rules jsonb NOT NULL CHECK (jsonb_typeof(rules) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (normalizer_key, normalizer_version)
);

INSERT INTO public.matter_identifier_normalizer_catalogue(
  normalizer_key, normalizer_version, rules
) VALUES (
  'official_reference_conservative', 1,
  jsonb_build_object(
    'unicode', 'NFKC',
    'case', 'upper',
    'whitespace', 'collapse_and_trim',
    'separator_spacing', 'trim_only',
    'unicode_dashes', 'ascii_hyphen',
    'preserve_digits', true,
    'preserve_separator_kind', true,
    'prefix_aliases', jsonb_build_object()
  )
);

CREATE TABLE public.matter_identifier_kind_catalogue (
  identifier_kind public.matter_identifier_kind NOT NULL,
  catalogue_version integer NOT NULL CHECK (catalogue_version >= 1),
  normalizer_key text NOT NULL,
  normalizer_version integer NOT NULL,
  identity_eligible boolean NOT NULL,
  suggestion_only boolean NOT NULL,
  allowed_roles public.matter_identifier_role[] NOT NULL CHECK (
    cardinality(allowed_roles) > 0
    AND allowed_roles <@ ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (identifier_kind, catalogue_version),
  CONSTRAINT matter_identifier_kind_catalogue_normalizer_fkey
    FOREIGN KEY (normalizer_key, normalizer_version)
    REFERENCES public.matter_identifier_normalizer_catalogue(normalizer_key, normalizer_version)
    ON DELETE RESTRICT,
  CONSTRAINT matter_identifier_kind_catalogue_policy CHECK (
    (identifier_kind = 'other_official_reference' AND suggestion_only AND NOT identity_eligible)
    OR (identifier_kind <> 'other_official_reference' AND NOT suggestion_only AND identity_eligible)
  )
);

INSERT INTO public.matter_identifier_kind_catalogue(
  identifier_kind, catalogue_version, normalizer_key, normalizer_version,
  identity_eligible, suggestion_only, allowed_roles
) VALUES
  ('proceeding_case_id',1,'official_reference_conservative',1,true,false,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]),
  ('notice_reference',1,'official_reference_conservative',1,true,false,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]),
  ('order_reference',1,'official_reference_conservative',1,true,false,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]),
  ('appeal_reference',1,'official_reference_conservative',1,true,false,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]),
  ('court_case_number',1,'official_reference_conservative',1,true,false,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]),
  ('other_official_reference',1,'official_reference_conservative',1,false,true,ARRAY['self_identifier','outbound_mention']::public.matter_identifier_role[]);

CREATE OR REPLACE FUNCTION public.matter_identifier_catalogue_prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'Matter identifier catalogue rows are immutable; add a new version';
END $$;

CREATE TRIGGER matter_identifier_normalizer_catalogue_no_mutation
  BEFORE UPDATE OR DELETE ON public.matter_identifier_normalizer_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.matter_identifier_catalogue_prevent_mutation();
CREATE TRIGGER matter_identifier_kind_catalogue_no_mutation
  BEFORE UPDATE OR DELETE ON public.matter_identifier_kind_catalogue
  FOR EACH ROW EXECUTE FUNCTION public.matter_identifier_catalogue_prevent_mutation();

CREATE OR REPLACE FUNCTION public.normalize_matter_identifier_namespace_v1(
  p_namespace text
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $$
DECLARE
  v_value text;
BEGIN
  IF p_namespace IS NULL OR char_length(p_namespace) NOT BETWEEN 2 AND 160
     OR p_namespace ~ '[[:cntrl:]]' THEN
    RETURN NULL;
  END IF;
  v_value := upper(normalize(p_namespace, NFKC));
  v_value := regexp_replace(v_value, '[[:space:]]+', ' ', 'g');
  v_value := btrim(v_value);
  v_value := regexp_replace(v_value, '[[:space:]]*([/.:_-])[[:space:]]*', E'\\1', 'g');
  IF char_length(v_value) NOT BETWEEN 2 AND 160 OR v_value !~ '[[:alnum:]]' THEN
    RETURN NULL;
  END IF;
  RETURN v_value;
END $$;

CREATE OR REPLACE FUNCTION public.normalize_matter_identifier_value_v1(
  p_identifier_kind public.matter_identifier_kind,
  p_raw_value text
)
RETURNS TABLE(normalized_value text, normalized_components jsonb)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_value text;
  v_segments text[];
  v_segment text;
  v_prefix text;
  v_numeric_core text;
  v_year text;
BEGIN
  IF p_identifier_kind IS NULL OR p_raw_value IS NULL
     OR char_length(p_raw_value) NOT BETWEEN 1 AND 300
     OR p_raw_value ~ '[[:cntrl:]]' THEN
    RETURN;
  END IF;
  v_value := upper(normalize(p_raw_value, NFKC));
  v_value := translate(v_value, U&'\2010\2011\2012\2013\2014\2212', '------');
  v_value := regexp_replace(v_value, '[[:space:]]+', ' ', 'g');
  v_value := btrim(v_value);
  v_value := regexp_replace(v_value, '[[:space:]]*([/.:_-])[[:space:]]*', E'\\1', 'g');
  IF char_length(v_value) NOT BETWEEN 1 AND 300 OR v_value !~ '[[:alnum:]]' THEN
    RETURN;
  END IF;

  v_segments := regexp_split_to_array(v_value, '[/.:_-]+');
  FOREACH v_segment IN ARRAY v_segments LOOP
    IF v_prefix IS NULL AND v_segment ~ '^[[:alpha:] ]{1,80}$' THEN
      v_prefix := v_segment;
    END IF;
    IF v_numeric_core IS NULL AND v_segment ~ '^[0-9]{1,40}$' THEN
      v_numeric_core := v_segment;
    END IF;
    IF v_segment ~ '^(19|20)[0-9]{2}$' THEN
      v_year := v_segment;
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_value, jsonb_strip_nulls(jsonb_build_object(
    'kind', p_identifier_kind::text,
    'segments', to_jsonb(v_segments),
    'prefix', v_prefix,
    'numericCore', v_numeric_core,
    'year', v_year
  ));
END $$;

CREATE OR REPLACE FUNCTION public.matter_identifier_regions_are_valid(
  p_regions jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $$
DECLARE
  v_region jsonb;
  v_x numeric;
  v_y numeric;
  v_width numeric;
  v_height numeric;
BEGIN
  IF p_regions IS NULL OR jsonb_typeof(p_regions) <> 'array'
     OR jsonb_array_length(p_regions) > 16 THEN
    RETURN false;
  END IF;
  FOR v_region IN SELECT value FROM jsonb_array_elements(p_regions) LOOP
    IF jsonb_typeof(v_region) <> 'object'
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(v_region) AS key
         WHERE key NOT IN ('x','y','width','height')
       )
       OR NOT (v_region ?& ARRAY['x','y','width','height'])
       OR EXISTS (
         SELECT 1 FROM unnest(ARRAY['x','y','width','height']) AS key
         WHERE jsonb_typeof(v_region -> key) <> 'number'
       ) THEN
      RETURN false;
    END IF;
    v_x := (v_region ->> 'x')::numeric;
    v_y := (v_region ->> 'y')::numeric;
    v_width := (v_region ->> 'width')::numeric;
    v_height := (v_region ->> 'height')::numeric;
    IF v_x < 0 OR v_y < 0 OR v_width <= 0 OR v_height <= 0
       OR v_x + v_width > 1 OR v_y + v_height > 1 THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
EXCEPTION WHEN numeric_value_out_of_range THEN
  RETURN false;
END $$;

ALTER TABLE public.matters
  ADD CONSTRAINT matters_org_client_id_id_unique UNIQUE (org_id, client_id, id);
ALTER TABLE public.documents
  ADD CONSTRAINT documents_org_matter_id_id_unique UNIQUE (org_id, matter_id, id);
ALTER TABLE public.document_versions
  ADD CONSTRAINT document_versions_org_document_id_id_unique UNIQUE (org_id, document_id, id);

CREATE TABLE public.matter_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  client_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  identifier_kind public.matter_identifier_kind NOT NULL,
  identifier_role public.matter_identifier_role NOT NULL,
  catalogue_version integer NOT NULL,
  normalizer_key text NOT NULL,
  normalizer_version integer NOT NULL,
  identity_eligible boolean NOT NULL,
  issuer_namespace_raw text NOT NULL CHECK (
    char_length(issuer_namespace_raw) BETWEEN 2 AND 160
    AND issuer_namespace_raw !~ '[[:cntrl:]]'
  ),
  issuer_namespace_display text NOT NULL CHECK (
    char_length(issuer_namespace_display) BETWEEN 2 AND 160
    AND issuer_namespace_display !~ '[[:cntrl:]]'
  ),
  issuer_namespace_normalized text NOT NULL CHECK (
    char_length(issuer_namespace_normalized) BETWEEN 2 AND 160
    AND issuer_namespace_normalized !~ '[[:cntrl:]]'
  ),
  raw_value text NOT NULL CHECK (
    char_length(raw_value) BETWEEN 1 AND 300 AND raw_value !~ '[[:cntrl:]]'
  ),
  display_value text NOT NULL CHECK (
    char_length(display_value) BETWEEN 1 AND 300 AND display_value !~ '[[:cntrl:]]'
  ),
  normalized_value text NOT NULL CHECK (
    char_length(normalized_value) BETWEEN 1 AND 300 AND normalized_value !~ '[[:cntrl:]]'
  ),
  normalized_components jsonb NOT NULL CHECK (jsonb_typeof(normalized_components) = 'object'),
  evidence_document_id uuid,
  evidence_document_version_id uuid,
  evidence_page_number integer CHECK (evidence_page_number IS NULL OR evidence_page_number >= 1),
  evidence_quote text CHECK (
    evidence_quote IS NULL OR (
      char_length(evidence_quote) BETWEEN 1 AND 500 AND evidence_quote !~ '[[:cntrl:]]'
    )
  ),
  evidence_regions jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (
    public.matter_identifier_regions_are_valid(evidence_regions)
  ),
  evidence_purged_at timestamptz,
  verification_method public.matter_identifier_verification_method NOT NULL,
  verified_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  verified_at timestamptz,
  lifecycle_state public.matter_identifier_lifecycle NOT NULL DEFAULT 'active',
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  predecessor_identifier_id uuid,
  activated_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  revocation_reason text CHECK (
    revocation_reason IS NULL OR (
      char_length(revocation_reason) BETWEEN 1 AND 500 AND revocation_reason !~ '[[:cntrl:]]'
    )
  ),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT matter_identifiers_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT matter_identifiers_matter_lineage_fkey
    FOREIGN KEY (org_id, client_id, matter_id)
    REFERENCES public.matters(org_id, client_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_evidence_document_fkey
    FOREIGN KEY (org_id, matter_id, evidence_document_id)
    REFERENCES public.documents(org_id, matter_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_evidence_version_fkey
    FOREIGN KEY (org_id, evidence_document_id, evidence_document_version_id)
    REFERENCES public.document_versions(org_id, document_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_catalogue_fkey
    FOREIGN KEY (identifier_kind, catalogue_version)
    REFERENCES public.matter_identifier_kind_catalogue(identifier_kind, catalogue_version)
    ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_normalizer_fkey
    FOREIGN KEY (normalizer_key, normalizer_version)
    REFERENCES public.matter_identifier_normalizer_catalogue(normalizer_key, normalizer_version)
    ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_predecessor_fkey
    FOREIGN KEY (org_id, predecessor_identifier_id)
    REFERENCES public.matter_identifiers(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifiers_verification_shape CHECK (
    (verification_method = 'human_source'
      AND identifier_role = 'self_identifier'
      AND evidence_document_id IS NOT NULL
      AND evidence_document_version_id IS NOT NULL
      AND evidence_page_number IS NOT NULL
      AND evidence_quote IS NOT NULL
      AND evidence_purged_at IS NULL
      AND verified_by IS NOT NULL
      AND verified_at IS NOT NULL)
    OR (verification_method = 'human_source'
      AND evidence_document_id IS NULL
      AND evidence_document_version_id IS NULL
      AND evidence_page_number IS NULL
      AND evidence_quote IS NULL
      AND evidence_regions = '[]'::jsonb
      AND evidence_purged_at IS NOT NULL
      AND verified_by IS NOT NULL
      AND verified_at IS NOT NULL)
    OR (verification_method = 'unverified_suggestion'
      AND evidence_purged_at IS NULL
      AND verified_by IS NULL AND verified_at IS NULL)
  ),
  CONSTRAINT matter_identifiers_lifecycle_shape CHECK (
    (lifecycle_state = 'active'
      AND revoked_at IS NULL AND revoked_by IS NULL AND revocation_reason IS NULL)
    OR (lifecycle_state = 'revoked'
      AND revoked_at IS NOT NULL AND revoked_by IS NOT NULL AND revocation_reason IS NOT NULL)
  )
);

CREATE UNIQUE INDEX matter_identifiers_verified_identity_reservation
  ON public.matter_identifiers(
    org_id, issuer_namespace_normalized, identifier_kind, normalized_value
  )
  WHERE lifecycle_state = 'active'
    AND identifier_role = 'self_identifier'
    AND verification_method = 'human_source'
    AND identity_eligible;
CREATE INDEX matter_identifiers_active_matter_idx
  ON public.matter_identifiers(org_id, matter_id, identifier_kind, id)
  WHERE lifecycle_state = 'active';

CREATE TABLE public.matter_identifier_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  org_id uuid NOT NULL,
  client_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  identifier_id uuid NOT NULL,
  previous_identifier_id uuid,
  action public.matter_identifier_decision_action NOT NULL,
  reason text CHECK (
    reason IS NULL OR (char_length(reason) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]')
  ),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  resulting_identifier_revision bigint NOT NULL CHECK (resulting_identifier_revision >= 1),
  resulting_matter_revision bigint NOT NULL CHECK (resulting_matter_revision >= 1),
  idempotency_key uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT matter_identifier_decisions_identifier_fkey
    FOREIGN KEY (org_id, identifier_id)
    REFERENCES public.matter_identifiers(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifier_decisions_previous_fkey
    FOREIGN KEY (org_id, previous_identifier_id)
    REFERENCES public.matter_identifiers(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifier_decisions_matter_fkey
    FOREIGN KEY (org_id, client_id, matter_id)
    REFERENCES public.matters(org_id, client_id, id) ON DELETE RESTRICT
);
CREATE INDEX matter_identifier_decisions_history_idx
  ON public.matter_identifier_decisions(org_id, matter_id, decision_sequence);

CREATE TABLE public.matter_identifier_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('activate','correct','revoke')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  identifier_id uuid NOT NULL,
  previous_identifier_id uuid,
  result_identifier_revision bigint NOT NULL CHECK (result_identifier_revision >= 1),
  result_matter_revision bigint NOT NULL CHECK (result_matter_revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT matter_identifier_command_receipts_identifier_fkey
    FOREIGN KEY (org_id, identifier_id)
    REFERENCES public.matter_identifiers(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT matter_identifier_command_receipts_previous_fkey
    FOREIGN KEY (org_id, previous_identifier_id)
    REFERENCES public.matter_identifiers(org_id, id) ON DELETE RESTRICT
);
CREATE INDEX matter_identifier_command_receipts_actor_org_idx
  ON public.matter_identifier_command_receipts(actor_user_id, org_id, created_at DESC);

-- Preserve CaseChain's internal Matter code across active and Trash records.
DO $$
DECLARE
  v_matter_code_conflicts integer;
  v_client_year_groups integer;
  v_client_year_rows integer;
BEGIN
  SELECT count(*)::integer INTO v_matter_code_conflicts
  FROM (
    SELECT org_id, matter_code
    FROM public.matters
    WHERE matter_code IS NOT NULL
    GROUP BY org_id, matter_code
    HAVING count(*) > 1
  ) AS conflicts;
  IF v_matter_code_conflicts > 0 THEN
    RAISE EXCEPTION 'Matter-code audit found % duplicate organisation keys', v_matter_code_conflicts;
  END IF;

  SELECT count(*)::integer, coalesce(sum(grouped.row_count),0)::integer
  INTO v_client_year_groups, v_client_year_rows
  FROM (
    SELECT count(*) AS row_count
    FROM public.matters
    GROUP BY org_id, client_id, financial_year
    HAVING count(*) > 1
  ) AS grouped;
  RAISE NOTICE 'Matter identity audit: % duplicate client/year groups across % rows; no rows changed',
    v_client_year_groups, v_client_year_rows;

  IF to_regclass('public.idx_matters_unique_client_fy') IS NULL THEN
    RAISE EXCEPTION 'D09-T01 must retain idx_matters_unique_client_fy for D09-T02';
  END IF;
END $$;

DROP INDEX public.idx_matters_unique_active_org_code;
CREATE UNIQUE INDEX matters_org_matter_code_unique
  ON public.matters(org_id, matter_code)
  WHERE matter_code IS NOT NULL;

CREATE OR REPLACE FUNCTION public.matter_identifier_decisions_prevent_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $$
BEGIN
  RAISE EXCEPTION 'Matter identifier decisions are append-only';
END $$;
CREATE TRIGGER matter_identifier_decisions_no_mutation
  BEFORE UPDATE OR DELETE ON public.matter_identifier_decisions
  FOR EACH ROW EXECUTE FUNCTION public.matter_identifier_decisions_prevent_mutation();

CREATE OR REPLACE FUNCTION public.enforce_matter_identifier_decision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_identifier public.matter_identifiers%ROWTYPE;
BEGIN
  SELECT * INTO v_identifier
  FROM public.matter_identifiers AS identifier
  WHERE identifier.id = NEW.identifier_id
    AND identifier.org_id = NEW.org_id
    AND identifier.client_id = NEW.client_id
    AND identifier.matter_id = NEW.matter_id;
  IF v_identifier.id IS NULL
     OR v_identifier.revision <> NEW.resulting_identifier_revision
     OR NOT EXISTS (
       SELECT 1 FROM public.matters AS matter
       WHERE matter.id = NEW.matter_id AND matter.org_id = NEW.org_id
         AND matter.client_id = NEW.client_id
         AND matter.revision = NEW.resulting_matter_revision
     )
     OR (NEW.action = 'activate' AND (
       NEW.previous_identifier_id IS NOT NULL OR v_identifier.lifecycle_state <> 'active'
       OR v_identifier.predecessor_identifier_id IS NOT NULL
     ))
     OR (NEW.action = 'correct' AND (
       NEW.previous_identifier_id IS NULL OR v_identifier.lifecycle_state <> 'active'
       OR v_identifier.predecessor_identifier_id IS DISTINCT FROM NEW.previous_identifier_id
       OR NOT EXISTS (
         SELECT 1 FROM public.matter_identifiers AS previous
         WHERE previous.id = NEW.previous_identifier_id AND previous.org_id = NEW.org_id
           AND previous.matter_id = NEW.matter_id AND previous.lifecycle_state = 'revoked'
       )
     ))
     OR (NEW.action = 'revoke' AND (
       NEW.previous_identifier_id IS NOT NULL OR v_identifier.lifecycle_state <> 'revoked'
     )) THEN
    RAISE EXCEPTION 'Matter identifier decision lineage is invalid' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER matter_identifier_decisions_enforce_lineage
  BEFORE INSERT ON public.matter_identifier_decisions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_matter_identifier_decision();

-- Relationship and Matter-identifier mutations share the current ordinary
-- legal-work baseline. Suspended membership has no capabilities and Viewer is
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
      'document.metadata.decide','trash.document','trash.hierarchy',
      'relationship.manage','matter.identifier.manage'
    ]::text[]
    WHEN p_role = 'admin' THEN ARRAY[
      'team.view','team.invite.standard','team.role.manage_standard',
      'team.membership.suspend_standard','organisation.profile.manage',
      'organisation.operations.manage','trash.purge','trash.retention.manage',
      'document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','trash.hierarchy','relationship.manage','matter.identifier.manage'
    ]::text[]
    WHEN p_role = 'associate' THEN ARRAY[
      'team.view','document.view','document.intake.create','document.record.create',
      'document.intake.assign','document.intake.discard','document.version.attach',
      'document.version.replace','document.reprocess','document.metadata.decide',
      'trash.document','relationship.manage','matter.identifier.manage'
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
    organisation.owner_membership_id = membership.id, membership.state, 10,
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

CREATE OR REPLACE FUNCTION public.lock_matter_identifier_actor()
RETURNS TABLE(actor_user_id uuid, org_id uuid)
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
BEGIN
  IF v_actor IS NULL THEN RETURN; END IF;
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor
      AND membership.state IN ('active','suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN RETURN; END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation
  WHERE organisation.id = v_membership.org_id;
  IF NOT ('matter.identifier.manage' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner,false), v_membership.state
  ))) THEN RETURN; END IF;
  RETURN QUERY SELECT v_actor, v_membership.org_id;
END $$;

CREATE OR REPLACE FUNCTION public.matter_identifier_reason_is_safe(
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

CREATE OR REPLACE FUNCTION public.matter_identifier_evidence_is_current(
  p_org_id uuid,
  p_matter_id uuid,
  p_identifier_kind public.matter_identifier_kind,
  p_raw_value text,
  p_document_id uuid,
  p_document_version_id uuid,
  p_page_number integer,
  p_quote text,
  p_regions jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_value record;
  v_quote record;
  v_position integer;
  v_next_position integer;
  v_value_length integer;
  v_quote_length integer;
BEGIN
  IF p_org_id IS NULL OR p_matter_id IS NULL OR p_document_id IS NULL
     OR p_document_version_id IS NULL OR p_page_number IS NULL OR p_page_number < 1
     OR p_quote IS NULL OR char_length(p_quote) NOT BETWEEN 1 AND 500
     OR p_quote ~ '[[:cntrl:]]'
     OR NOT public.matter_identifier_regions_are_valid(p_regions)
     OR NOT EXISTS (
       SELECT 1
       FROM public.documents AS document
       JOIN public.document_versions AS version
         ON version.id = p_document_version_id
        AND version.org_id = document.org_id
        AND version.document_id = document.id
       WHERE document.id = p_document_id AND document.org_id = p_org_id
         AND document.matter_id = p_matter_id
         AND document.document_class = 'proceeding'
         AND document.record_state = 'active' AND document.deleted_at IS NULL
         AND document.current_version_id = version.id
         AND version.state = 'current' AND version.validation_state = 'valid'
         AND version.page_count IS NOT NULL AND p_page_number <= version.page_count
     ) THEN
    RETURN false;
  END IF;
  SELECT * INTO v_value
  FROM public.normalize_matter_identifier_value_v1(p_identifier_kind,p_raw_value);
  SELECT * INTO v_quote
  FROM public.normalize_matter_identifier_value_v1(p_identifier_kind,p_quote);
  IF v_value.normalized_value IS NULL OR v_quote.normalized_value IS NULL THEN
    RETURN false;
  END IF;

  v_value_length := char_length(v_value.normalized_value);
  v_quote_length := char_length(v_quote.normalized_value);
  v_position := strpos(v_quote.normalized_value,v_value.normalized_value);
  WHILE v_position > 0 LOOP
    IF (v_position = 1 OR substring(v_quote.normalized_value FROM v_position - 1 FOR 1) !~ '[[:alnum:]]')
       AND (v_position + v_value_length > v_quote_length
         OR substring(v_quote.normalized_value FROM v_position + v_value_length FOR 1) !~ '[[:alnum:]]') THEN
      RETURN true;
    END IF;
    v_next_position := strpos(
      substring(v_quote.normalized_value FROM v_position + 1),
      v_value.normalized_value
    );
    IF v_next_position = 0 THEN
      EXIT;
    END IF;
    v_position := v_position + v_next_position;
  END LOOP;
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public.enforce_matter_identifier()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_catalogue public.matter_identifier_kind_catalogue%ROWTYPE;
  v_normalized record;
  v_namespace text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF pg_catalog.pg_trigger_depth() = 2
       AND OLD.evidence_document_version_id IS NOT NULL
       AND OLD.evidence_purged_at IS NULL
       AND NEW.evidence_document_id IS NULL
       AND NEW.evidence_document_version_id IS NULL
       AND NEW.evidence_page_number IS NULL
       AND NEW.evidence_quote IS NULL
       AND NEW.evidence_regions = '[]'::jsonb
       AND NEW.evidence_purged_at IS NOT NULL
       AND NEW.issuer_namespace_raw = OLD.issuer_namespace_normalized
       AND NEW.issuer_namespace_display = OLD.issuer_namespace_normalized
       AND NEW.raw_value = OLD.normalized_value
       AND NEW.display_value = OLD.normalized_value
       AND NEW.revision = OLD.revision + 1
       AND NEW.org_id = OLD.org_id
       AND NEW.client_id = OLD.client_id
       AND NEW.matter_id = OLD.matter_id
       AND NEW.identifier_kind = OLD.identifier_kind
       AND NEW.identifier_role = OLD.identifier_role
       AND NEW.catalogue_version = OLD.catalogue_version
       AND NEW.normalizer_key = OLD.normalizer_key
       AND NEW.normalizer_version = OLD.normalizer_version
       AND NEW.identity_eligible = OLD.identity_eligible
       AND NEW.issuer_namespace_normalized = OLD.issuer_namespace_normalized
       AND NEW.normalized_value = OLD.normalized_value
       AND NEW.normalized_components = OLD.normalized_components
       AND NEW.verification_method = OLD.verification_method
       AND NEW.verified_by IS NOT DISTINCT FROM OLD.verified_by
       AND NEW.verified_at IS NOT DISTINCT FROM OLD.verified_at
       AND NEW.lifecycle_state = OLD.lifecycle_state
       AND NEW.predecessor_identifier_id IS NOT DISTINCT FROM OLD.predecessor_identifier_id
       AND NEW.activated_at = OLD.activated_at
       AND NEW.revoked_at IS NOT DISTINCT FROM OLD.revoked_at
       AND NEW.revoked_by IS NOT DISTINCT FROM OLD.revoked_by
       AND NEW.revocation_reason IS NOT DISTINCT FROM OLD.revocation_reason THEN
      RETURN NEW;
    END IF;
    IF NEW.org_id IS DISTINCT FROM OLD.org_id
       OR NEW.client_id IS DISTINCT FROM OLD.client_id
       OR NEW.matter_id IS DISTINCT FROM OLD.matter_id
       OR NEW.identifier_kind IS DISTINCT FROM OLD.identifier_kind
       OR NEW.identifier_role IS DISTINCT FROM OLD.identifier_role
       OR NEW.catalogue_version IS DISTINCT FROM OLD.catalogue_version
       OR NEW.normalizer_key IS DISTINCT FROM OLD.normalizer_key
       OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
       OR NEW.identity_eligible IS DISTINCT FROM OLD.identity_eligible
       OR NEW.issuer_namespace_raw IS DISTINCT FROM OLD.issuer_namespace_raw
       OR NEW.issuer_namespace_display IS DISTINCT FROM OLD.issuer_namespace_display
       OR NEW.issuer_namespace_normalized IS DISTINCT FROM OLD.issuer_namespace_normalized
       OR NEW.raw_value IS DISTINCT FROM OLD.raw_value
       OR NEW.display_value IS DISTINCT FROM OLD.display_value
       OR NEW.normalized_value IS DISTINCT FROM OLD.normalized_value
       OR NEW.normalized_components IS DISTINCT FROM OLD.normalized_components
       OR NEW.evidence_document_id IS DISTINCT FROM OLD.evidence_document_id
       OR NEW.evidence_document_version_id IS DISTINCT FROM OLD.evidence_document_version_id
       OR NEW.evidence_page_number IS DISTINCT FROM OLD.evidence_page_number
       OR NEW.evidence_quote IS DISTINCT FROM OLD.evidence_quote
       OR NEW.evidence_regions IS DISTINCT FROM OLD.evidence_regions
       OR NEW.evidence_purged_at IS DISTINCT FROM OLD.evidence_purged_at
       OR NEW.verification_method IS DISTINCT FROM OLD.verification_method
       OR NEW.verified_by IS DISTINCT FROM OLD.verified_by
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
       OR NEW.predecessor_identifier_id IS DISTINCT FROM OLD.predecessor_identifier_id
       OR NEW.activated_at IS DISTINCT FROM OLD.activated_at
       OR OLD.lifecycle_state <> 'active'
       OR NEW.lifecycle_state <> 'revoked'
       OR NEW.revision <> OLD.revision + 1
       OR NEW.revoked_at IS NULL
       OR NEW.revoked_by IS NULL
       OR NEW.revocation_reason IS NULL THEN
      RAISE EXCEPTION 'Matter identifier updates are limited to one governed revocation' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.revision <> 1 OR NEW.lifecycle_state <> 'active'
     OR NEW.revoked_at IS NOT NULL OR NEW.revoked_by IS NOT NULL
     OR NEW.revocation_reason IS NOT NULL THEN
    RAISE EXCEPTION 'New Matter identifiers must begin at active revision one' USING ERRCODE = '23514';
  END IF;
  SELECT * INTO v_catalogue
  FROM public.matter_identifier_kind_catalogue AS catalogue
  WHERE catalogue.identifier_kind = NEW.identifier_kind
    AND catalogue.catalogue_version = NEW.catalogue_version;
  IF v_catalogue.identifier_kind IS NULL
     OR NEW.normalizer_key <> v_catalogue.normalizer_key
     OR NEW.normalizer_version <> v_catalogue.normalizer_version
     OR NEW.identity_eligible <> v_catalogue.identity_eligible
     OR NOT NEW.identifier_role = ANY(v_catalogue.allowed_roles)
     OR (v_catalogue.suggestion_only AND NEW.verification_method <> 'unverified_suggestion') THEN
    RAISE EXCEPTION 'Matter identifier catalogue snapshot is invalid' USING ERRCODE = '23514';
  END IF;
  IF NEW.normalizer_key <> 'official_reference_conservative'
     OR NEW.normalizer_version <> 1 THEN
    RAISE EXCEPTION 'Matter identifier normalizer is unsupported' USING ERRCODE = '23514';
  END IF;
  v_namespace := public.normalize_matter_identifier_namespace_v1(NEW.issuer_namespace_raw);
  SELECT * INTO v_normalized
  FROM public.normalize_matter_identifier_value_v1(NEW.identifier_kind, NEW.raw_value);
  IF v_namespace IS NULL OR NEW.issuer_namespace_normalized <> v_namespace
     OR v_normalized.normalized_value IS NULL
     OR NEW.normalized_value <> v_normalized.normalized_value
     OR NEW.normalized_components <> v_normalized.normalized_components THEN
    RAISE EXCEPTION 'Matter identifier normalization snapshot is invalid' USING ERRCODE = '23514';
  END IF;
  IF NEW.verification_method = 'human_source'
     AND NOT public.matter_identifier_evidence_is_current(
       NEW.org_id,NEW.matter_id,NEW.identifier_kind,NEW.raw_value,
       NEW.evidence_document_id,NEW.evidence_document_version_id,
       NEW.evidence_page_number,NEW.evidence_quote,NEW.evidence_regions
     ) THEN
    RAISE EXCEPTION 'Matter identifier source evidence is invalid' USING ERRCODE = '23514';
  END IF;
  IF NEW.predecessor_identifier_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.matter_identifiers AS predecessor
    WHERE predecessor.id = NEW.predecessor_identifier_id
      AND predecessor.org_id = NEW.org_id
      AND predecessor.matter_id = NEW.matter_id
      AND predecessor.lifecycle_state = 'revoked'
  ) THEN
    RAISE EXCEPTION 'Matter identifier correction predecessor is invalid' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER matter_identifiers_enforce_contract
  BEFORE INSERT OR UPDATE ON public.matter_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.enforce_matter_identifier();

CREATE OR REPLACE FUNCTION public.scrub_matter_identifier_evidence_before_version_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
BEGIN
  UPDATE public.matter_identifiers AS identifier
  SET issuer_namespace_raw = identifier.issuer_namespace_normalized,
    issuer_namespace_display = identifier.issuer_namespace_normalized,
    raw_value = identifier.normalized_value,
    display_value = identifier.normalized_value,
    evidence_document_id = NULL,
    evidence_document_version_id = NULL,
    evidence_page_number = NULL,
    evidence_quote = NULL,
    evidence_regions = '[]'::jsonb,
    evidence_purged_at = clock_timestamp(),
    revision = identifier.revision + 1,
    updated_at = clock_timestamp()
  WHERE identifier.org_id = OLD.org_id
    AND identifier.evidence_document_version_id = OLD.id
    AND identifier.evidence_purged_at IS NULL;
  RETURN OLD;
END $$;

CREATE TRIGGER document_versions_scrub_matter_identifier_evidence
  BEFORE DELETE ON public.document_versions
  FOR EACH ROW EXECUTE FUNCTION public.scrub_matter_identifier_evidence_before_version_delete();

INSERT INTO public.activity_event_definitions(
  event_type,event_version,category,subject_types,default_visibility,
  metadata_contract,renderer_key
) VALUES (
  'matter.identifier_changed',1,'record',ARRAY['matter'],'matter',
  '{"change":"code","identifier_kind":"code"}'::jsonb,
  'matter.identifier_changed'
);

CREATE OR REPLACE FUNCTION public.perform_matter_identifier_command(
  p_command text,
  p_identifier_id uuid,
  p_matter_id uuid,
  p_expected_identifier_revision bigint,
  p_expected_matter_revision bigint,
  p_identifier_kind public.matter_identifier_kind,
  p_identifier_role public.matter_identifier_role,
  p_issuer_namespace text,
  p_raw_value text,
  p_display_value text,
  p_evidence_document_id uuid,
  p_evidence_document_version_id uuid,
  p_evidence_page_number integer,
  p_evidence_quote text,
  p_evidence_regions jsonb,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  code text,
  identifier_id uuid,
  previous_identifier_id uuid,
  identifier_revision bigint,
  matter_revision bigint,
  replayed boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_actor record;
  v_receipt public.matter_identifier_command_receipts%ROWTYPE;
  v_matter public.matters%ROWTYPE;
  v_previous public.matter_identifiers%ROWTYPE;
  v_identifier public.matter_identifiers%ROWTYPE;
  v_conflict public.matter_identifiers%ROWTYPE;
  v_catalogue public.matter_identifier_kind_catalogue%ROWTYPE;
  v_normalized record;
  v_namespace text;
  v_reason text := nullif(btrim(p_reason),'');
  v_display_value text := nullif(btrim(p_display_value),'');
  v_fingerprint text;
  v_effective_matter_id uuid;
  v_change text;
BEGIN
  IF p_command NOT IN ('activate','correct','revoke') OR p_idempotency_key IS NULL
     OR p_expected_matter_revision IS NULL OR p_expected_matter_revision < 1
     OR (p_command = 'activate' AND (
       p_identifier_id IS NOT NULL OR p_matter_id IS NULL
       OR p_expected_identifier_revision IS NOT NULL
     ))
     OR (p_command IN ('correct','revoke') AND (
       p_identifier_id IS NULL OR p_matter_id IS NOT NULL
       OR p_expected_identifier_revision IS NULL OR p_expected_identifier_revision < 1
     ))
     OR NOT public.matter_identifier_reason_is_safe(
       v_reason,p_command IN ('correct','revoke')
     ) THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    RETURN;
  END IF;
  IF p_command IN ('activate','correct') AND (
    p_identifier_kind IS NULL OR p_identifier_role IS NULL
    OR p_issuer_namespace IS NULL OR p_raw_value IS NULL OR v_display_value IS NULL
    OR p_evidence_document_id IS NULL OR p_evidence_document_version_id IS NULL
    OR p_evidence_page_number IS NULL OR p_evidence_quote IS NULL
    OR p_evidence_regions IS NULL
  ) THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text,147)
  );
  SELECT * INTO v_actor FROM public.lock_matter_identifier_actor();
  IF v_actor.actor_user_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command',p_command,'identifier_id',p_identifier_id,'matter_id',p_matter_id,
    'expected_identifier_revision',p_expected_identifier_revision,
    'expected_matter_revision',p_expected_matter_revision,
    'identifier_kind',p_identifier_kind,'identifier_role',p_identifier_role,
    'issuer_namespace',p_issuer_namespace,'raw_value',p_raw_value,
    'display_value',v_display_value,'evidence_document_id',p_evidence_document_id,
    'evidence_document_version_id',p_evidence_document_version_id,
    'evidence_page_number',p_evidence_page_number,'evidence_quote',p_evidence_quote,
    'evidence_regions',p_evidence_regions,'reason',v_reason
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt
  FROM public.matter_identifier_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor.actor_user_id
       OR v_receipt.org_id <> v_actor.org_id
       OR v_receipt.command <> p_command
       OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    ELSE
      RETURN QUERY SELECT 'ok',v_receipt.identifier_id,v_receipt.previous_identifier_id,
        v_receipt.result_identifier_revision,v_receipt.result_matter_revision,true;
    END IF;
    RETURN;
  END IF;

  IF p_command = 'activate' THEN
    v_effective_matter_id := p_matter_id;
  ELSE
    SELECT * INTO v_previous
    FROM public.matter_identifiers AS identifier
    WHERE identifier.id = p_identifier_id AND identifier.org_id = v_actor.org_id;
    IF v_previous.id IS NULL THEN
      RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;
    v_effective_matter_id := v_previous.matter_id;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor.org_id::text || ':' || v_effective_matter_id::text,147)
  );
  SELECT matter.* INTO v_matter
  FROM public.matters AS matter
  JOIN public.clients AS client
    ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = v_effective_matter_id AND matter.org_id = v_actor.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR UPDATE OF matter,client;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
    RETURN;
  END IF;
  IF v_matter.revision <> p_expected_matter_revision THEN
    RETURN QUERY SELECT 'conflict',NULL::uuid,NULL::uuid,NULL::bigint,v_matter.revision,false;
    RETURN;
  END IF;

  IF p_command IN ('correct','revoke') THEN
    SELECT * INTO v_previous
    FROM public.matter_identifiers AS identifier
    WHERE identifier.id = p_identifier_id AND identifier.org_id = v_actor.org_id
      AND identifier.matter_id = v_matter.id
    FOR UPDATE;
    IF v_previous.id IS NULL THEN
      RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;
    IF v_previous.lifecycle_state <> 'active' THEN
      RETURN QUERY SELECT 'identifier_unavailable',NULL::uuid,NULL::uuid,v_previous.revision,v_matter.revision,false;
      RETURN;
    END IF;
    IF v_previous.revision <> p_expected_identifier_revision THEN
      RETURN QUERY SELECT 'conflict',v_previous.id,NULL::uuid,v_previous.revision,v_matter.revision,false;
      RETURN;
    END IF;
  END IF;

  IF p_command IN ('activate','correct') THEN
    IF p_identifier_role <> 'self_identifier' THEN
      RETURN QUERY SELECT 'invalid_identifier_role',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;
    SELECT * INTO v_catalogue
    FROM public.matter_identifier_kind_catalogue AS catalogue
    WHERE catalogue.identifier_kind = p_identifier_kind
    ORDER BY catalogue.catalogue_version DESC LIMIT 1;
    IF v_catalogue.identifier_kind IS NULL THEN
      RETURN QUERY SELECT 'unsupported_kind',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;
    IF v_catalogue.suggestion_only OR NOT v_catalogue.identity_eligible THEN
      RETURN QUERY SELECT 'suggestion_only',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;
    v_namespace := public.normalize_matter_identifier_namespace_v1(p_issuer_namespace);
    SELECT * INTO v_normalized
    FROM public.normalize_matter_identifier_value_v1(p_identifier_kind,p_raw_value);
    IF v_namespace IS NULL OR v_normalized.normalized_value IS NULL
       OR char_length(v_display_value) > 300 THEN
      RETURN QUERY SELECT 'invalid_identifier',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;

    PERFORM 1 FROM public.documents AS document
    WHERE document.id = p_evidence_document_id ORDER BY document.id FOR UPDATE;
    PERFORM 1 FROM public.document_versions AS version
    WHERE version.id = p_evidence_document_version_id FOR KEY SHARE;
    IF NOT public.matter_identifier_evidence_is_current(
      v_actor.org_id,v_matter.id,p_identifier_kind,p_raw_value,
      p_evidence_document_id,p_evidence_document_version_id,
      p_evidence_page_number,p_evidence_quote,p_evidence_regions
    ) THEN
      RETURN QUERY SELECT 'invalid_evidence',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    END IF;

    SELECT * INTO v_conflict
    FROM public.matter_identifiers AS identifier
    WHERE identifier.org_id = v_actor.org_id
      AND identifier.issuer_namespace_normalized = v_namespace
      AND identifier.identifier_kind = p_identifier_kind
      AND identifier.normalized_value = v_normalized.normalized_value
      AND identifier.lifecycle_state = 'active'
      AND identifier.identifier_role = 'self_identifier'
      AND identifier.verification_method = 'human_source'
      AND identifier.identity_eligible
      AND identifier.id IS DISTINCT FROM p_identifier_id
    FOR UPDATE;
    IF v_conflict.id IS NOT NULL THEN
      RETURN QUERY SELECT CASE WHEN v_conflict.matter_id = v_matter.id
          THEN 'duplicate_active' ELSE 'identifier_conflict' END,
        v_conflict.id,NULL::uuid,v_conflict.revision,v_matter.revision,false;
      RETURN;
    END IF;
  END IF;

  BEGIN
    IF p_command = 'activate' THEN
      INSERT INTO public.matter_identifiers(
        org_id,client_id,matter_id,identifier_kind,identifier_role,
        catalogue_version,normalizer_key,normalizer_version,identity_eligible,
        issuer_namespace_raw,issuer_namespace_display,issuer_namespace_normalized,
        raw_value,display_value,normalized_value,normalized_components,
        evidence_document_id,evidence_document_version_id,evidence_page_number,
        evidence_quote,evidence_regions,verification_method,verified_by,verified_at
      ) VALUES (
        v_actor.org_id,v_matter.client_id,v_matter.id,p_identifier_kind,p_identifier_role,
        v_catalogue.catalogue_version,v_catalogue.normalizer_key,v_catalogue.normalizer_version,
        v_catalogue.identity_eligible,p_issuer_namespace,btrim(p_issuer_namespace),v_namespace,
        p_raw_value,v_display_value,v_normalized.normalized_value,v_normalized.normalized_components,
        p_evidence_document_id,p_evidence_document_version_id,p_evidence_page_number,
        p_evidence_quote,p_evidence_regions,'human_source',v_actor.actor_user_id,now()
      ) RETURNING * INTO v_identifier;
      v_change := 'activated';
    ELSIF p_command = 'correct' THEN
      UPDATE public.matter_identifiers AS identifier
      SET lifecycle_state = 'revoked',revision = identifier.revision + 1,
        revoked_at = clock_timestamp(),revoked_by = v_actor.actor_user_id,
        revocation_reason = v_reason,updated_at = clock_timestamp()
      WHERE identifier.id = v_previous.id
      RETURNING * INTO v_previous;
      INSERT INTO public.matter_identifiers(
        org_id,client_id,matter_id,identifier_kind,identifier_role,
        catalogue_version,normalizer_key,normalizer_version,identity_eligible,
        issuer_namespace_raw,issuer_namespace_display,issuer_namespace_normalized,
        raw_value,display_value,normalized_value,normalized_components,
        evidence_document_id,evidence_document_version_id,evidence_page_number,
        evidence_quote,evidence_regions,verification_method,verified_by,verified_at,
        predecessor_identifier_id
      ) VALUES (
        v_actor.org_id,v_matter.client_id,v_matter.id,p_identifier_kind,p_identifier_role,
        v_catalogue.catalogue_version,v_catalogue.normalizer_key,v_catalogue.normalizer_version,
        v_catalogue.identity_eligible,p_issuer_namespace,btrim(p_issuer_namespace),v_namespace,
        p_raw_value,v_display_value,v_normalized.normalized_value,v_normalized.normalized_components,
        p_evidence_document_id,p_evidence_document_version_id,p_evidence_page_number,
        p_evidence_quote,p_evidence_regions,'human_source',v_actor.actor_user_id,now(),
        v_previous.id
      ) RETURNING * INTO v_identifier;
      v_change := 'corrected';
    ELSE
      UPDATE public.matter_identifiers AS identifier
      SET lifecycle_state = 'revoked',revision = identifier.revision + 1,
        revoked_at = clock_timestamp(),revoked_by = v_actor.actor_user_id,
        revocation_reason = v_reason,updated_at = clock_timestamp()
      WHERE identifier.id = v_previous.id
      RETURNING * INTO v_identifier;
      v_change := 'revoked';
    END IF;

    UPDATE public.matters AS matter
    SET revision = matter.revision + 1
    WHERE matter.id = v_matter.id AND matter.org_id = v_actor.org_id
    RETURNING * INTO v_matter;

    INSERT INTO public.matter_identifier_decisions(
      org_id,client_id,matter_id,identifier_id,previous_identifier_id,
      action,reason,actor_user_id,resulting_identifier_revision,
      resulting_matter_revision,idempotency_key
    ) VALUES (
      v_actor.org_id,v_matter.client_id,v_matter.id,v_identifier.id,
      CASE WHEN p_command = 'correct' THEN v_previous.id ELSE NULL END,
      p_command::public.matter_identifier_decision_action,v_reason,v_actor.actor_user_id,
      v_identifier.revision,v_matter.revision,p_idempotency_key
    );

    PERFORM public.append_activity_event(
      v_actor.org_id,'matter.identifier_changed',1::smallint,'user',
      v_actor.actor_user_id,'Member','matter',v_matter.id,v_matter.client_id,
      v_matter.id,'Matter','Matter identifier ' || v_change,
      jsonb_build_object('change',v_change,'identifier_kind',v_identifier.identifier_kind::text),
      'matter',v_matter.id,NULL,p_idempotency_key,NULL,
      'matter.identifier.' || p_command || '.' || p_idempotency_key::text,now()
    );

    INSERT INTO public.matter_identifier_command_receipts(
      org_id,actor_user_id,idempotency_key,command,request_fingerprint,
      identifier_id,previous_identifier_id,result_identifier_revision,
      result_matter_revision
    ) VALUES (
      v_actor.org_id,v_actor.actor_user_id,p_idempotency_key,p_command,v_fingerprint,
      v_identifier.id,CASE WHEN p_command = 'correct' THEN v_previous.id ELSE NULL END,
      v_identifier.revision,v_matter.revision
    );
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT 'identifier_conflict',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    WHEN check_violation OR foreign_key_violation THEN
      RETURN QUERY SELECT 'context_unavailable',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
    WHEN others THEN
      RETURN QUERY SELECT 'write_failed',NULL::uuid,NULL::uuid,NULL::bigint,NULL::bigint,false;
      RETURN;
  END;

  RETURN QUERY SELECT 'ok',v_identifier.id,
    CASE WHEN p_command = 'correct' THEN v_previous.id ELSE NULL::uuid END,
    v_identifier.revision,v_matter.revision,false;
END $$;

CREATE OR REPLACE FUNCTION public.activate_matter_identifier(
  p_matter_id uuid,
  p_expected_matter_revision bigint,
  p_identifier_kind public.matter_identifier_kind,
  p_identifier_role public.matter_identifier_role,
  p_issuer_namespace text,
  p_raw_value text,
  p_display_value text,
  p_evidence_document_id uuid,
  p_evidence_document_version_id uuid,
  p_evidence_page_number integer,
  p_evidence_quote text,
  p_evidence_regions jsonb,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  code text, identifier_id uuid, identifier_revision bigint,
  matter_revision bigint, replayed boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT result.code,result.identifier_id,result.identifier_revision,
    result.matter_revision,result.replayed
  FROM public.perform_matter_identifier_command(
    'activate',NULL,p_matter_id,NULL,p_expected_matter_revision,
    p_identifier_kind,p_identifier_role,p_issuer_namespace,p_raw_value,p_display_value,
    p_evidence_document_id,p_evidence_document_version_id,p_evidence_page_number,
    p_evidence_quote,p_evidence_regions,p_reason,p_idempotency_key
  ) AS result
$$;

CREATE OR REPLACE FUNCTION public.correct_matter_identifier(
  p_identifier_id uuid,
  p_expected_identifier_revision bigint,
  p_expected_matter_revision bigint,
  p_identifier_kind public.matter_identifier_kind,
  p_identifier_role public.matter_identifier_role,
  p_issuer_namespace text,
  p_raw_value text,
  p_display_value text,
  p_evidence_document_id uuid,
  p_evidence_document_version_id uuid,
  p_evidence_page_number integer,
  p_evidence_quote text,
  p_evidence_regions jsonb,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  code text, identifier_id uuid, previous_identifier_id uuid,
  identifier_revision bigint, matter_revision bigint, replayed boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT result.code,result.identifier_id,result.previous_identifier_id,
    result.identifier_revision,result.matter_revision,result.replayed
  FROM public.perform_matter_identifier_command(
    'correct',p_identifier_id,NULL,p_expected_identifier_revision,
    p_expected_matter_revision,p_identifier_kind,p_identifier_role,
    p_issuer_namespace,p_raw_value,p_display_value,p_evidence_document_id,
    p_evidence_document_version_id,p_evidence_page_number,p_evidence_quote,
    p_evidence_regions,p_reason,p_idempotency_key
  ) AS result
$$;

CREATE OR REPLACE FUNCTION public.revoke_matter_identifier(
  p_identifier_id uuid,
  p_expected_identifier_revision bigint,
  p_expected_matter_revision bigint,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  code text, identifier_id uuid, identifier_revision bigint,
  matter_revision bigint, replayed boolean
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT result.code,result.identifier_id,result.identifier_revision,
    result.matter_revision,result.replayed
  FROM public.perform_matter_identifier_command(
    'revoke',p_identifier_id,NULL,p_expected_identifier_revision,
    p_expected_matter_revision,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    p_reason,p_idempotency_key
  ) AS result
$$;

CREATE OR REPLACE FUNCTION public.read_matter_identifiers(
  p_matter_id uuid
)
RETURNS TABLE(
  outcome text,
  identifiers jsonb,
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
    JOIN public.clients AS client
      ON client.id = matter.client_id AND client.org_id = matter.org_id
    WHERE matter.id = p_matter_id AND matter.org_id = v_org
      AND matter.record_state = 'active' AND matter.deleted_at IS NULL
      AND client.record_state = 'active' AND client.deleted_at IS NULL
  ) THEN
    RETURN QUERY SELECT 'unavailable','[]'::jsonb,NULL::text,clock_timestamp();
    RETURN;
  END IF;

  RETURN QUERY
  WITH projected AS (
    SELECT identifier.*,
      evidence.id IS NOT NULL AND version.id IS NOT NULL AS evidence_available
    FROM public.matter_identifiers AS identifier
    LEFT JOIN public.documents AS evidence
      ON evidence.id = identifier.evidence_document_id
     AND evidence.org_id = identifier.org_id
     AND evidence.matter_id = identifier.matter_id
     AND evidence.record_state = 'active' AND evidence.deleted_at IS NULL
    LEFT JOIN public.document_versions AS version
      ON version.id = identifier.evidence_document_version_id
     AND version.org_id = identifier.org_id
     AND version.document_id = evidence.id
    WHERE identifier.org_id = v_org AND identifier.matter_id = p_matter_id
      AND identifier.lifecycle_state = 'active'
      AND identifier.identifier_role = 'self_identifier'
      AND identifier.verification_method = 'human_source'
      AND identifier.identity_eligible
  )
  SELECT 'ok',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',projected.id,
      'revision',projected.revision,
      'identifierKind',projected.identifier_kind,
      'identifierRole',projected.identifier_role,
      'catalogueVersion',projected.catalogue_version,
      'normalizerVersion',projected.normalizer_version,
      'issuerNamespaceDisplay',projected.issuer_namespace_display,
      'issuerNamespaceNormalized',projected.issuer_namespace_normalized,
      'rawValue',projected.raw_value,
      'displayValue',projected.display_value,
      'normalizedValue',projected.normalized_value,
      'normalizedComponents',projected.normalized_components,
      'verificationMethod',projected.verification_method,
      'verifiedAt',projected.verified_at,
      'evidenceAvailable',projected.evidence_available,
      'evidenceDocumentId',CASE WHEN projected.evidence_available THEN projected.evidence_document_id END,
      'evidenceDocumentVersionId',CASE WHEN projected.evidence_available THEN projected.evidence_document_version_id END,
      'evidencePageNumber',CASE WHEN projected.evidence_available THEN projected.evidence_page_number END
    ) ORDER BY projected.identifier_kind,projected.normalized_value,projected.id)
    FROM projected
  ),'[]'::jsonb),md5(coalesce((
    SELECT string_agg(concat_ws(':',projected.id,projected.revision,
      projected.identifier_kind,projected.normalized_value),'|' ORDER BY projected.id)
    FROM projected
  ),'')),clock_timestamp();
END $$;

ALTER TABLE public.matter_identifier_normalizer_catalogue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_normalizer_catalogue FORCE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_kind_catalogue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_kind_catalogue FORCE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifiers FORCE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_decisions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_identifier_command_receipts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.matter_identifier_normalizer_catalogue,
  public.matter_identifier_kind_catalogue,public.matter_identifiers,
  public.matter_identifier_decisions,public.matter_identifier_command_receipts
  FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.matter_identifier_catalogue_prevent_mutation(),
  public.normalize_matter_identifier_namespace_v1(text),
  public.normalize_matter_identifier_value_v1(public.matter_identifier_kind,text),
  public.matter_identifier_regions_are_valid(jsonb),
  public.enforce_matter_identifier(),
  public.matter_identifier_decisions_prevent_mutation(),
  public.enforce_matter_identifier_decision(),
  public.lock_matter_identifier_actor(),
  public.matter_identifier_reason_is_safe(text,boolean),
  public.matter_identifier_evidence_is_current(uuid,uuid,public.matter_identifier_kind,text,uuid,uuid,integer,text,jsonb),
  public.scrub_matter_identifier_evidence_before_version_delete(),
  public.perform_matter_identifier_command(text,uuid,uuid,bigint,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

REVOKE ALL ON FUNCTION public.activate_matter_identifier(uuid,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid),
  public.correct_matter_identifier(uuid,bigint,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid),
  public.revoke_matter_identifier(uuid,bigint,bigint,text,uuid),
  public.read_matter_identifiers(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.activate_matter_identifier(uuid,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid),
  public.correct_matter_identifier(uuid,bigint,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid),
  public.revoke_matter_identifier(uuid,bigint,bigint,text,uuid),
  public.read_matter_identifiers(uuid)
  TO authenticated;

COMMENT ON TABLE public.matter_identifiers IS
  'Governed Matter external identifiers. Verified identity-eligible self keys reserve their namespace across active and Trash Matters; raw values and source evidence remain private.';
COMMENT ON FUNCTION public.activate_matter_identifier(uuid,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid) IS
  'Authenticated human activation with current source evidence, aggregate CAS, replay protection, namespaced reservation, append-only history, and canonical Activity.';
COMMENT ON FUNCTION public.correct_matter_identifier(uuid,bigint,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid) IS
  'Authenticated atomic correction that revokes the former identifier and activates a source-evidenced successor without releasing an unsafe intermediate state.';
COMMENT ON FUNCTION public.revoke_matter_identifier(uuid,bigint,bigint,text,uuid) IS
  'Authenticated reason-required revocation with identifier and Matter CAS, replay protection, append-only history, and canonical Activity.';
COMMENT ON FUNCTION public.read_matter_identifiers(uuid) IS
  'Narrow authenticated active-Matter projection. Evidence quotes, regions, actor identifiers, decisions, receipts, suggestions, and Trash identifiers are never returned.';

COMMIT;
