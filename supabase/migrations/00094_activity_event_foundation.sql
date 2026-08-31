-- Work plan step 2: Activity's private, append-only foundation.  This is an
-- expand-only contract: activity_logs remains the live compatibility history
-- until a later producer/reader cut-over explicitly adopts these commands.
BEGIN;

CREATE TYPE public.activity_actor_kind AS ENUM ('user', 'system', 'integration');
CREATE TYPE public.activity_visibility AS ENUM ('organisation', 'matter');
CREATE TYPE public.activity_projector_delivery_state AS ENUM ('pending', 'leased', 'delivered', 'dead_letter');

CREATE OR REPLACE FUNCTION public.activity_safe_text(p_value text, p_max_length integer)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT p_value IS NOT NULL AND char_length(btrim(p_value)) BETWEEN 1 AND p_max_length
    AND p_value !~ '[[:cntrl:]]'
    AND p_value !~* '(https?://|s3://|gs://|data:|signed.?url|credential|secret|token|password|api.?key|embedding|storage.?path|object.?key|raw.?content|@)'
$$;

CREATE OR REPLACE FUNCTION public.activity_metadata_is_safe(p_contract jsonb, p_metadata jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE key_name text; value jsonb; expected text;
BEGIN
  IF jsonb_typeof(p_contract) <> 'object' OR jsonb_typeof(p_metadata) <> 'object' THEN RETURN false; END IF;
  FOR key_name, value IN SELECT item.key, item.value FROM jsonb_each(p_metadata) AS item LOOP
    expected := p_contract ->> key_name;
    IF expected IS NULL OR lower(key_name) ~ '(content|text|body|description|email|url|path|storage|object|credential|secret|token|password|embedding|provider|payload|raw)' THEN RETURN false; END IF;
    IF expected='code' AND (jsonb_typeof(value)<>'string' OR value #>> '{}' !~ '^[a-z][a-z0-9_.:-]{0,79}$') THEN RETURN false; END IF;
    IF expected='label' AND (jsonb_typeof(value)<>'string' OR NOT public.activity_safe_text(value #>> '{}',120)) THEN RETURN false; END IF;
    IF expected='integer' AND (jsonb_typeof(value)<>'number' OR (value #>> '{}') !~ '^-?[0-9]{1,9}$') THEN RETURN false; END IF;
    IF expected='boolean' AND jsonb_typeof(value)<>'boolean' THEN RETURN false; END IF;
  END LOOP;
  RETURN NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_contract) AS required_key WHERE left(required_key,1)='!' AND NOT (p_metadata ? substr(required_key,2)));
END $$;

CREATE TABLE public.activity_event_definitions (
  event_type text NOT NULL CHECK (event_type ~ '^[a-z][a-z0-9_.]{1,80}$'),
  event_version smallint NOT NULL CHECK (event_version >= 1),
  category text NOT NULL CHECK (category ~ '^[a-z][a-z0-9_.-]{1,80}$'),
  subject_types text[] NOT NULL CHECK (cardinality(subject_types)>0 AND subject_types <@ ARRAY['organisation','client','matter','document','trash_operation']::text[]),
  default_visibility public.activity_visibility NOT NULL,
  metadata_contract jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata_contract)='object'),
  renderer_key text NOT NULL CHECK (renderer_key ~ '^[a-z][a-z0-9_.-]{1,100}$'),
  lifecycle text NOT NULL DEFAULT 'active' CHECK (lifecycle IN ('active','retired')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_type,event_version)
);

CREATE TABLE public.activity_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  client_id uuid REFERENCES public.clients(id) ON DELETE RESTRICT,
  matter_id uuid REFERENCES public.matters(id) ON DELETE RESTRICT,
  actor_kind public.activity_actor_kind NOT NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_snapshot text NOT NULL CHECK (public.activity_safe_text(actor_snapshot,160)),
  event_type text NOT NULL,
  event_version smallint NOT NULL,
  subject_type text NOT NULL CHECK (subject_type=ANY(ARRAY['organisation','client','matter','document','trash_operation']::text[])),
  subject_id uuid NOT NULL,
  subject_snapshot text NOT NULL CHECK (public.activity_safe_text(subject_snapshot,200)),
  summary text NOT NULL CHECK (public.activity_safe_text(summary,280)),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  visibility public.activity_visibility NOT NULL,
  renderer_key text NOT NULL,
  target_type text NOT NULL CHECK (target_type=ANY(ARRAY['organisation','client','matter','document','trash_operation']::text[])),
  target_id uuid NOT NULL,
  target_version_id uuid,
  correlation_id uuid,
  causation_event_id uuid REFERENCES public.activity_events(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL UNIQUE CHECK (idempotency_key ~ '^[A-Za-z0-9._:-]{1,200}$'),
  occurred_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_events_definition_fkey FOREIGN KEY(event_type,event_version) REFERENCES public.activity_event_definitions(event_type,event_version) ON DELETE RESTRICT,
  CONSTRAINT activity_events_actor_shape CHECK ((actor_kind='user' AND actor_id IS NOT NULL) OR (actor_kind='system' AND actor_id IS NULL) OR (actor_kind='integration' AND actor_id IS NOT NULL))
);
CREATE INDEX activity_events_org_occurred_idx ON public.activity_events(org_id,occurred_at DESC,id DESC);
CREATE INDEX activity_events_matter_occurred_idx ON public.activity_events(org_id,matter_id,occurred_at DESC,id DESC) WHERE matter_id IS NOT NULL;

CREATE TABLE public.activity_projector_outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_event_id uuid NOT NULL UNIQUE REFERENCES public.activity_events(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  projector_key text NOT NULL DEFAULT 'activity.core.v1' CHECK (projector_key='activity.core.v1'),
  delivery_state public.activity_projector_delivery_state NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
  lease_token uuid, lease_expires_at timestamptz, delivered_at timestamptz, failed_at timestamptz,
  last_error_code text CHECK (last_error_code IS NULL OR last_error_code ~ '^[a-z][a-z0-9_.-]{1,79}$'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_projector_outbox_state CHECK (
    (delivery_state='pending' AND lease_token IS NULL AND lease_expires_at IS NULL AND delivered_at IS NULL AND failed_at IS NULL)
    OR (delivery_state='leased' AND lease_token IS NOT NULL AND lease_expires_at IS NOT NULL AND delivered_at IS NULL AND failed_at IS NULL)
    OR (delivery_state='delivered' AND lease_token IS NULL AND lease_expires_at IS NULL AND delivered_at IS NOT NULL AND failed_at IS NULL)
    OR (delivery_state='dead_letter' AND lease_token IS NULL AND lease_expires_at IS NULL AND delivered_at IS NULL AND failed_at IS NOT NULL)
  )
);
CREATE INDEX activity_projector_outbox_due_idx ON public.activity_projector_outbox_events(created_at,id) WHERE delivery_state='pending';
CREATE TABLE public.activity_projector_receipts (
  projector_key text NOT NULL CHECK (projector_key='activity.core.v1'),
  activity_event_id uuid NOT NULL REFERENCES public.activity_events(id) ON DELETE RESTRICT,
  outbox_event_id uuid NOT NULL REFERENCES public.activity_projector_outbox_events(id) ON DELETE RESTRICT,
  projected_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(projector_key,activity_event_id)
);

CREATE OR REPLACE FUNCTION public.activity_events_prevent_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'Activity events are append-only'; END $$;
CREATE TRIGGER activity_events_no_mutation BEFORE UPDATE OR DELETE ON public.activity_events FOR EACH ROW EXECUTE FUNCTION public.activity_events_prevent_mutation();
CREATE OR REPLACE FUNCTION public.activity_definitions_prevent_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'Activity definitions are migration-owned'; END $$;
CREATE TRIGGER activity_definitions_no_mutation BEFORE UPDATE OR DELETE ON public.activity_event_definitions FOR EACH ROW EXECUTE FUNCTION public.activity_definitions_prevent_mutation();

CREATE OR REPLACE FUNCTION public.activity_validate_subject(
  p_org_id uuid,p_subject_type text,p_subject_id uuid,p_client_id uuid,p_matter_id uuid,p_target_type text,p_target_id uuid,p_target_version_id uuid
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
DECLARE actual_client uuid; actual_matter uuid; actual_document uuid; target_org uuid; root_type public.trash_resource_type;
BEGIN
  IF p_subject_type='organisation' THEN IF p_subject_id<>p_org_id OR p_client_id IS NOT NULL OR p_matter_id IS NOT NULL THEN RETURN false; END IF;
  ELSIF p_subject_type='client' THEN SELECT id INTO actual_client FROM public.clients WHERE id=p_subject_id AND org_id=p_org_id; IF actual_client IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS NOT NULL THEN RETURN false; END IF;
  ELSIF p_subject_type='matter' THEN SELECT client_id INTO actual_client FROM public.matters WHERE id=p_subject_id AND org_id=p_org_id; IF actual_client IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM p_subject_id THEN RETURN false; END IF;
  ELSIF p_subject_type='document' THEN SELECT m.client_id,d.matter_id INTO actual_client,actual_matter FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id WHERE d.id=p_subject_id AND d.org_id=p_org_id; IF actual_matter IS NULL OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM actual_matter THEN RETURN false; END IF;
  ELSIF p_subject_type='trash_operation' THEN
    SELECT root_resource_type,root_client_id,root_matter_id,root_document_id INTO root_type,actual_client,actual_matter,actual_document FROM public.trash_operations WHERE id=p_subject_id AND org_id=p_org_id;
    IF root_type IS NULL THEN RETURN false; END IF;
    IF root_type='matter' THEN SELECT client_id INTO actual_client FROM public.matters WHERE id=actual_matter AND org_id=p_org_id;
    ELSIF root_type='document' THEN SELECT m.client_id,d.matter_id INTO actual_client,actual_matter FROM public.documents d JOIN public.matters m ON m.id=d.matter_id AND m.org_id=d.org_id WHERE d.id=actual_document AND d.org_id=p_org_id; END IF;
    IF (root_type='client' AND actual_client IS NULL) OR (root_type IN ('matter','document') AND (actual_client IS NULL OR actual_matter IS NULL)) OR p_client_id IS DISTINCT FROM actual_client OR p_matter_id IS DISTINCT FROM actual_matter THEN RETURN false; END IF;
  ELSE RETURN false; END IF;
  IF p_target_type='organisation' THEN RETURN p_target_version_id IS NULL AND p_target_id=p_org_id; END IF;
  IF p_target_type='client' THEN SELECT org_id INTO target_org FROM public.clients WHERE id=p_target_id; ELSIF p_target_type='matter' THEN SELECT org_id INTO target_org FROM public.matters WHERE id=p_target_id; ELSIF p_target_type='document' THEN SELECT org_id INTO target_org FROM public.documents WHERE id=p_target_id; ELSIF p_target_type='trash_operation' THEN SELECT org_id INTO target_org FROM public.trash_operations WHERE id=p_target_id; ELSE RETURN false; END IF;
  IF target_org IS DISTINCT FROM p_org_id OR (p_target_type<>'document' AND p_target_version_id IS NOT NULL) THEN RETURN false; END IF;
  RETURN p_target_version_id IS NULL OR EXISTS (SELECT 1 FROM public.document_versions version WHERE version.id=p_target_version_id AND version.org_id=p_org_id AND version.document_id=p_target_id);
END $$;

CREATE OR REPLACE FUNCTION public.append_activity_event(
  p_org_id uuid,p_event_type text,p_event_version smallint,p_actor_kind public.activity_actor_kind,p_actor_id uuid,p_actor_snapshot text,
  p_subject_type text,p_subject_id uuid,p_client_id uuid,p_matter_id uuid,p_subject_snapshot text,p_summary text,p_metadata jsonb,
  p_target_type text,p_target_id uuid,p_target_version_id uuid,p_correlation_id uuid,p_causation_event_id uuid,p_idempotency_key text,p_occurred_at timestamptz DEFAULT now()
) RETURNS TABLE(activity_event_id uuid,outbox_event_id uuid,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE definition public.activity_event_definitions%ROWTYPE; existing public.activity_events%ROWTYPE; snapshot text; created_event uuid; created_outbox uuid;
BEGIN
  IF p_org_id IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{1,200}$' OR p_occurred_at IS NULL OR p_occurred_at>now()+interval '5 minutes' THEN RAISE EXCEPTION 'invalid Activity append request'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_idempotency_key));
  SELECT * INTO existing FROM public.activity_events WHERE idempotency_key=p_idempotency_key;
  IF existing.id IS NOT NULL THEN
    IF existing.org_id<>p_org_id OR existing.subject_type<>p_subject_type OR existing.subject_id<>p_subject_id OR existing.event_type<>p_event_type OR existing.event_version<>p_event_version THEN RAISE EXCEPTION 'Activity idempotency key is bound to another tenant or subject'; END IF;
    RETURN QUERY SELECT existing.id,(SELECT outbox.id FROM public.activity_projector_outbox_events AS outbox WHERE outbox.activity_event_id=existing.id),true; RETURN;
  END IF;
  SELECT * INTO definition FROM public.activity_event_definitions WHERE event_type=p_event_type AND event_version=p_event_version AND lifecycle='active';
  IF definition.event_type IS NULL OR NOT p_subject_type=ANY(definition.subject_types) OR NOT public.activity_metadata_is_safe(definition.metadata_contract,coalesce(p_metadata,'{}'::jsonb)) OR NOT public.activity_validate_subject(p_org_id,p_subject_type,p_subject_id,p_client_id,p_matter_id,p_target_type,p_target_id,p_target_version_id) THEN RAISE EXCEPTION 'Activity definition, lineage, metadata, or locator is invalid'; END IF;
  IF p_actor_kind IN ('user','integration') THEN SELECT coalesce(nullif(btrim(profile.display_name),''),CASE WHEN p_actor_kind='integration' THEN 'Integration member' ELSE 'Member' END) INTO snapshot FROM public.organisation_memberships membership LEFT JOIN public.user_profiles profile ON profile.user_id=membership.user_id WHERE membership.org_id=p_org_id AND membership.user_id=p_actor_id AND membership.state='active'; IF snapshot IS NULL THEN RAISE EXCEPTION 'Activity actor is not an active organisation member'; END IF;
  ELSE snapshot:=p_actor_snapshot; END IF;
  IF NOT public.activity_safe_text(snapshot,160) OR NOT public.activity_safe_text(p_subject_snapshot,200) OR NOT public.activity_safe_text(p_summary,280) OR (p_actor_kind='system' AND p_actor_id IS NOT NULL) OR (p_actor_kind='integration' AND p_actor_id IS NULL) THEN RAISE EXCEPTION 'Activity snapshot or actor is unsafe'; END IF;
  IF p_causation_event_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.activity_events WHERE id=p_causation_event_id AND org_id=p_org_id) THEN RAISE EXCEPTION 'Activity causation must remain tenant-scoped'; END IF;
  INSERT INTO public.activity_events(org_id,client_id,matter_id,actor_kind,actor_id,actor_snapshot,event_type,event_version,subject_type,subject_id,subject_snapshot,summary,metadata,visibility,renderer_key,target_type,target_id,target_version_id,correlation_id,causation_event_id,idempotency_key,occurred_at)
  VALUES(p_org_id,p_client_id,p_matter_id,p_actor_kind,p_actor_id,snapshot,p_event_type,p_event_version,p_subject_type,p_subject_id,p_subject_snapshot,p_summary,coalesce(p_metadata,'{}'::jsonb),definition.default_visibility,definition.renderer_key,p_target_type,p_target_id,p_target_version_id,p_correlation_id,p_causation_event_id,p_idempotency_key,p_occurred_at) RETURNING id INTO created_event;
  INSERT INTO public.activity_projector_outbox_events(activity_event_id,org_id) VALUES(created_event,p_org_id) RETURNING id INTO created_outbox;
  RETURN QUERY SELECT created_event,created_outbox,false;
END $$;

CREATE OR REPLACE FUNCTION public.lease_activity_projector_events(p_limit integer DEFAULT 25,p_lease_seconds integer DEFAULT 120)
RETURNS TABLE(outbox_event_id uuid,activity_event_id uuid,org_id uuid,lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF p_limit NOT BETWEEN 1 AND 100 OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN RAISE EXCEPTION 'invalid Activity projector lease request'; END IF;
  UPDATE public.activity_projector_outbox_events SET delivery_state='pending',lease_token=NULL,lease_expires_at=NULL,last_error_code='lease_expired',updated_at=now() WHERE delivery_state='leased' AND lease_expires_at<=now() AND attempt_count<5;
  UPDATE public.activity_projector_outbox_events SET delivery_state='dead_letter',lease_token=NULL,lease_expires_at=NULL,failed_at=now(),last_error_code='lease_expired',updated_at=now() WHERE delivery_state='leased' AND lease_expires_at<=now() AND attempt_count>=5;
  RETURN QUERY WITH candidates AS (SELECT id FROM public.activity_projector_outbox_events WHERE delivery_state='pending' ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT p_limit), leased AS (UPDATE public.activity_projector_outbox_events o SET delivery_state='leased',attempt_count=o.attempt_count+1,lease_token=gen_random_uuid(),lease_expires_at=now()+make_interval(secs=>p_lease_seconds),updated_at=now() FROM candidates WHERE o.id=candidates.id RETURNING o.id,o.activity_event_id,o.org_id,o.lease_token) SELECT * FROM leased;
END $$;
CREATE OR REPLACE FUNCTION public.complete_activity_projector_event(p_outbox_event_id uuid,p_lease_token uuid)
RETURNS TABLE(code text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE event_row public.activity_projector_outbox_events%ROWTYPE;
BEGIN SELECT * INTO event_row FROM public.activity_projector_outbox_events WHERE id=p_outbox_event_id FOR UPDATE; IF event_row.id IS NULL THEN RETURN QUERY SELECT 'not_available'::text; RETURN; END IF; IF event_row.delivery_state='delivered' THEN RETURN QUERY SELECT 'already_delivered'::text; RETURN; END IF; IF event_row.delivery_state<>'leased' OR event_row.lease_token IS DISTINCT FROM p_lease_token OR event_row.lease_expires_at<=now() THEN RETURN QUERY SELECT 'stale_lease'::text; RETURN; END IF; INSERT INTO public.activity_projector_receipts(projector_key,activity_event_id,outbox_event_id) VALUES(event_row.projector_key,event_row.activity_event_id,event_row.id) ON CONFLICT DO NOTHING; UPDATE public.activity_projector_outbox_events SET delivery_state='delivered',lease_token=NULL,lease_expires_at=NULL,delivered_at=now(),updated_at=now() WHERE id=event_row.id; RETURN QUERY SELECT 'ok'::text; END $$;

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key) VALUES
 ('client.created',1,'record',ARRAY['client'],'organisation','{}','client.created'),
 ('client.updated',1,'record',ARRAY['client'],'organisation','{"changed_field":"code"}','client.updated'),
 ('document.lifecycle_changed',1,'record',ARRAY['document'],'matter','{"change":"code"}','document.lifecycle_changed'),
 ('document.link_changed',1,'relationship',ARRAY['document'],'matter','{"link_action":"code"}','document.link_changed'),
 ('resource.trashed',1,'lifecycle',ARRAY['client','matter','document','trash_operation'],'organisation','{"resource_type":"code"}','resource.trashed'),
 ('resource.restored',1,'lifecycle',ARRAY['client','matter','document','trash_operation'],'organisation','{"resource_type":"code"}','resource.restored'),
 ('resource.purged',1,'lifecycle',ARRAY['client','matter','document','trash_operation'],'organisation','{"resource_type":"code"}','resource.purged'),
 ('organisation.invitation_changed',1,'security',ARRAY['organisation'],'organisation','{"transition":"code"}','organisation.invitation_changed'),
 ('organisation.configuration_changed',1,'security',ARRAY['organisation'],'organisation','{"change":"code"}','organisation.configuration_changed');

ALTER TABLE public.activity_event_definitions ENABLE ROW LEVEL SECURITY; ALTER TABLE public.activity_event_definitions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.activity_events ENABLE ROW LEVEL SECURITY; ALTER TABLE public.activity_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.activity_projector_outbox_events ENABLE ROW LEVEL SECURITY; ALTER TABLE public.activity_projector_outbox_events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.activity_projector_receipts ENABLE ROW LEVEL SECURITY; ALTER TABLE public.activity_projector_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.activity_event_definitions,public.activity_events,public.activity_projector_outbox_events,public.activity_projector_receipts FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.activity_safe_text(text,integer),public.activity_metadata_is_safe(jsonb,jsonb),public.activity_validate_subject(uuid,text,uuid,uuid,uuid,text,uuid,uuid),public.activity_events_prevent_mutation(),public.activity_definitions_prevent_mutation() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz),public.lease_activity_projector_events(integer,integer),public.complete_activity_projector_event(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz),public.lease_activity_projector_events(integer,integer),public.complete_activity_projector_event(uuid,uuid) TO service_role;

COMMENT ON TABLE public.activity_events IS 'Append-only Activity contract. No existing producer or reader adopts it until the later cut-over.';
COMMENT ON TABLE public.activity_projector_outbox_events IS 'Service-only transactional Activity projector wake contract; no consumer is adopted in this foundation migration.';
COMMIT;
