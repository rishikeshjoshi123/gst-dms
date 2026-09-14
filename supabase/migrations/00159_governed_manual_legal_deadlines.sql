-- D11-T11: governed manual, verified, date-only legal deadlines in an active Matter.
-- Extracted candidates, scheduled events, assignment and reminder delivery remain out of scope.
-- The current Activity/outbox registries have no deadline subject/envelope; this slice
-- therefore relies on its immutable domain history and does not invent an unsafe event.
BEGIN;

ALTER TABLE public.deadlines
  ADD COLUMN org_id uuid REFERENCES public.organisations(id) ON DELETE RESTRICT,
  ADD COLUMN title text,
  ADD COLUMN legal_type text,
  ADD COLUMN origin text,
  ADD COLUMN verification_state text,
  ADD COLUMN lifecycle text,
  ADD COLUMN current_revision bigint,
  ADD COLUMN created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

WITH normalized_legacy AS (
  SELECT d.id,CASE
    WHEN char_length(btrim(regexp_replace(coalesce(d.description,''),'[[:cntrl:]]',' ','g')))<2 THEN 'Legacy deadline'
    ELSE left(btrim(regexp_replace(d.description,'[[:cntrl:]]',' ','g')),1000)
  END obligation
  FROM public.deadlines d
)
UPDATE public.deadlines d SET
  org_id=m.org_id,
  description=normalized_legacy.obligation,
  title=left(normalized_legacy.obligation,160),
  legal_type=CASE d.type::text
    WHEN 'appeal_window' THEN 'appeal_due'
    WHEN 'pre_deposit' THEN 'payment_or_predeposit_due'
    WHEN 'reply_deadline' THEN 'reply_due'
    WHEN 'stay_application' THEN 'stay_application_due'
    ELSE 'other_legal' END,
  origin='legacy', verification_state='provisional',
  lifecycle=CASE WHEN d.is_resolved THEN 'satisfied' ELSE 'open' END,
  current_revision=1
FROM public.matters m,normalized_legacy WHERE m.id=d.matter_id AND normalized_legacy.id=d.id;

ALTER TABLE public.deadlines
  ALTER COLUMN org_id SET NOT NULL,
  ALTER COLUMN title SET NOT NULL,
  ALTER COLUMN legal_type SET NOT NULL,
  ALTER COLUMN origin SET NOT NULL,
  ALTER COLUMN verification_state SET NOT NULL,
  ALTER COLUMN lifecycle SET NOT NULL,
  ALTER COLUMN current_revision SET NOT NULL,
  ADD CONSTRAINT deadlines_org_matter_fkey FOREIGN KEY(org_id,matter_id)
    REFERENCES public.matters(org_id,id) ON DELETE RESTRICT,
  ADD CONSTRAINT deadlines_title_check CHECK(char_length(title) BETWEEN 2 AND 160 AND title=btrim(title) AND title !~ '[[:cntrl:]]'),
  ADD CONSTRAINT deadlines_description_check CHECK(description IS NOT NULL AND char_length(description) BETWEEN 2 AND 1000 AND description=btrim(description) AND description !~ '[[:cntrl:]]'),
  ADD CONSTRAINT deadlines_legal_type_check CHECK(legal_type IN ('reply_due','appeal_due','payment_or_predeposit_due','compliance_due','stay_application_due','other_legal')),
  ADD CONSTRAINT deadlines_origin_check CHECK(origin IN ('manual','legacy')),
  ADD CONSTRAINT deadlines_verification_check CHECK(verification_state IN ('verified','provisional')),
  ADD CONSTRAINT deadlines_lifecycle_check CHECK(lifecycle IN ('open','satisfied','cancelled')),
  ADD CONSTRAINT deadlines_revision_check CHECK(current_revision>=1),
  ADD CONSTRAINT deadlines_manual_shape_check CHECK(origin<>'manual' OR (verification_state='verified' AND document_id IS NULL AND created_by IS NOT NULL)),
  ADD CONSTRAINT deadlines_legacy_resolution_compatibility CHECK(is_resolved=(lifecycle<>'open'));
CREATE INDEX deadlines_manual_matter_agenda_idx ON public.deadlines(org_id,matter_id,lifecycle,due_date,id)
  WHERE origin='manual' AND verification_state='verified';
ALTER TABLE public.deadlines ADD CONSTRAINT deadlines_org_id_id_unique UNIQUE(org_id,id);

CREATE TABLE public.deadline_versions(
  deadline_id uuid NOT NULL REFERENCES public.deadlines(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL,
  revision bigint NOT NULL CHECK(revision>=1),
  title text NOT NULL CHECK(char_length(title) BETWEEN 2 AND 160 AND title=btrim(title) AND title !~ '[[:cntrl:]]'),
  obligation text NOT NULL CHECK(char_length(obligation) BETWEEN 2 AND 1000 AND obligation=btrim(obligation) AND obligation !~ '[[:cntrl:]]'),
  legal_type text NOT NULL CHECK(legal_type IN ('reply_due','appeal_due','payment_or_predeposit_due','compliance_due','stay_application_due','other_legal')),
  due_date date NOT NULL,
  manual_basis text NOT NULL CHECK(char_length(manual_basis) BETWEEN 2 AND 500 AND manual_basis=btrim(manual_basis) AND manual_basis !~ '[[:cntrl:]]'),
  amendment_reason text CHECK(amendment_reason IS NULL OR (char_length(amendment_reason) BETWEEN 2 AND 500 AND amendment_reason=btrim(amendment_reason) AND amendment_reason !~ '[[:cntrl:]]')),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(deadline_id,revision),
  FOREIGN KEY(org_id,deadline_id) REFERENCES public.deadlines(org_id,id) ON DELETE RESTRICT,
  CHECK((revision=1 AND amendment_reason IS NULL) OR (revision>1 AND amendment_reason IS NOT NULL))
);

CREATE TABLE public.deadline_outcomes(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deadline_id uuid NOT NULL REFERENCES public.deadlines(id) ON DELETE RESTRICT,
  org_id uuid NOT NULL,
  revision bigint NOT NULL CHECK(revision>=2),
  outcome text NOT NULL CHECK(outcome IN ('satisfied','cancelled')),
  reason text CHECK(
    (outcome='satisfied' AND (reason IS NULL OR (char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]')))
    OR (outcome='cancelled' AND char_length(reason) BETWEEN 2 AND 500 AND reason=btrim(reason) AND reason !~ '[[:cntrl:]]')
  ),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(deadline_id),
  FOREIGN KEY(org_id,deadline_id) REFERENCES public.deadlines(org_id,id) ON DELETE RESTRICT
);

CREATE TABLE public.deadline_command_receipts(
  idempotency_key uuid PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  command text NOT NULL CHECK(command IN ('create','amend','satisfy','cancel')),
  request_fingerprint text NOT NULL CHECK(request_fingerprint ~ '^[0-9a-f]{64}$'),
  deadline_id uuid NOT NULL,
  result_revision bigint NOT NULL CHECK(result_revision>=1),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(org_id,deadline_id) REFERENCES public.deadlines(org_id,id) ON DELETE RESTRICT
);

ALTER TABLE public.deadline_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_outcomes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_outcomes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deadline_command_receipts FORCE ROW LEVEL SECURITY;

CREATE FUNCTION public.deadline_append_only_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
  RAISE EXCEPTION 'Deadline history is append-only' USING ERRCODE='55000';
END $$;
CREATE TRIGGER deadline_versions_append_only BEFORE UPDATE OR DELETE ON public.deadline_versions FOR EACH ROW EXECUTE FUNCTION public.deadline_append_only_guard();
CREATE TRIGGER deadline_outcomes_append_only BEFORE UPDATE OR DELETE ON public.deadline_outcomes FOR EACH ROW EXECUTE FUNCTION public.deadline_append_only_guard();
CREATE TRIGGER deadline_receipts_append_only BEFORE UPDATE OR DELETE ON public.deadline_command_receipts FOR EACH ROW EXECUTE FUNCTION public.deadline_append_only_guard();

-- Only canonical commands may create/delete or change authoritative fields.
CREATE FUNCTION public.deadline_command_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$ BEGIN
  IF current_setting('casechain.deadline_command',true) IS DISTINCT FROM 'on' THEN
    IF TG_OP='UPDATE' AND (NEW.org_id,NEW.matter_id,NEW.document_id,NEW.type,NEW.due_date,NEW.description,NEW.is_resolved,NEW.resolved_by,NEW.resolved_at,NEW.title,NEW.legal_type,NEW.origin,NEW.verification_state,NEW.lifecycle,NEW.current_revision,NEW.created_by)
      IS NOT DISTINCT FROM (OLD.org_id,OLD.matter_id,OLD.document_id,OLD.type,OLD.due_date,OLD.description,OLD.is_resolved,OLD.resolved_by,OLD.resolved_at,OLD.title,OLD.legal_type,OLD.origin,OLD.verification_state,OLD.lifecycle,OLD.current_revision,OLD.created_by) THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Use a canonical deadline command' USING ERRCODE='42501';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER deadlines_canonical_writes BEFORE INSERT OR UPDATE OR DELETE ON public.deadlines FOR EACH ROW EXECUTE FUNCTION public.deadline_command_guard();

DROP POLICY IF EXISTS deadlines_insert ON public.deadlines;
DROP POLICY IF EXISTS deadlines_update ON public.deadlines;
DROP POLICY IF EXISTS deadlines_delete ON public.deadlines;
DROP POLICY IF EXISTS deadlines_select ON public.deadlines;
ALTER TABLE public.deadlines FORCE ROW LEVEL SECURITY;
REVOKE SELECT,INSERT,UPDATE,DELETE ON public.deadlines FROM PUBLIC,authenticated,anon;
REVOKE ALL ON public.deadline_versions,public.deadline_outcomes,public.deadline_command_receipts FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO public.deadline_versions(deadline_id,org_id,revision,title,obligation,legal_type,due_date,manual_basis,actor_user_id)
SELECT d.id,d.org_id,1,d.title,d.description,d.legal_type,d.due_date,'Legacy record; verification not established.',coalesce(d.created_by,m.created_by)
FROM public.deadlines d JOIN public.organisations m ON m.id=d.org_id;

CREATE FUNCTION public.deadline_actor_for_matter(p_matter_id uuid,p_mutation boolean)
RETURNS TABLE(actor_user_id uuid,org_id uuid,client_id uuid,timezone text,can_mutate boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE member record; owner boolean;
BEGIN
  SELECT * INTO member FROM public.current_active_tenant_membership();
  IF member.membership_id IS NULL THEN RETURN; END IF;
  IF p_mutation THEN
    PERFORM 1 FROM public.organisation_memberships m WHERE m.id=member.membership_id AND m.state='active' FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM 1 FROM public.matters m JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
      WHERE m.id=p_matter_id AND m.org_id=member.org_id AND m.record_state='active' AND m.deleted_at IS NULL AND m.work_state='active'
        AND c.record_state='active' AND c.deleted_at IS NULL FOR UPDATE OF m,c;
    IF NOT FOUND THEN RETURN; END IF;
  END IF;
  SELECT o.owner_membership_id=member.membership_id INTO owner FROM public.organisations o WHERE o.id=member.org_id;
  IF NOT ('document.view'=ANY(public.organisation_member_capabilities(member.role,coalesce(owner,false),'active'::public.organisation_membership_state))) THEN RETURN; END IF;
  RETURN QUERY SELECT auth.uid(),member.org_id,m.client_id,s.timezone,
    (coalesce(owner,false) OR member.role IN ('admin','associate'))
  FROM public.matters m JOIN public.clients c ON c.id=m.client_id AND c.org_id=m.org_id
  JOIN public.organisation_operational_settings s ON s.org_id=m.org_id
  WHERE m.id=p_matter_id AND m.org_id=member.org_id
    AND m.record_state='active' AND m.deleted_at IS NULL AND m.work_state='active'
    AND c.record_state='active' AND c.deleted_at IS NULL
    AND EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=s.timezone)
    AND (NOT p_mutation OR coalesce(owner,false) OR member.role IN ('admin','associate'));
END $$;

CREATE FUNCTION public.deadline_fingerprint(p_payload jsonb) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,public AS $$
 SELECT encode(extensions.digest(convert_to(p_payload::text,'utf8'),'sha256'),'hex')
$$;

CREATE FUNCTION public.create_manual_legal_deadline(p_matter_id uuid,p_title text,p_obligation text,p_legal_type text,p_due_date date,p_manual_basis text,p_idempotency_key uuid)
RETURNS TABLE(code text,deadline_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; receipt public.deadline_command_receipts%ROWTYPE; fingerprint text; created public.deadlines%ROWTYPE;
BEGIN
  p_title:=btrim(p_title); p_obligation:=btrim(p_obligation); p_manual_basis:=btrim(p_manual_basis);
  IF p_matter_id IS NULL OR p_title IS NULL OR p_obligation IS NULL OR p_manual_basis IS NULL OR p_due_date IS NULL OR p_idempotency_key IS NULL OR p_legal_type IS NULL
    OR char_length(p_title) NOT BETWEEN 2 AND 160 OR p_title ~ '[[:cntrl:]]'
    OR char_length(p_obligation) NOT BETWEEN 2 AND 1000 OR p_obligation ~ '[[:cntrl:]]'
    OR char_length(p_manual_basis) NOT BETWEEN 2 AND 500 OR p_manual_basis ~ '[[:cntrl:]]'
    OR p_legal_type NOT IN ('reply_due','appeal_due','payment_or_predeposit_due','compliance_due','stay_application_due','other_legal') THEN
    RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO actor FROM public.deadline_actor_for_matter(p_matter_id,true);
  IF actor.actor_user_id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('command','create','matter_id',p_matter_id,'title',p_title,'obligation',p_obligation,'legal_type',p_legal_type,'due_date',p_due_date,'manual_basis',p_manual_basis));
  SELECT * INTO receipt FROM public.deadline_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.idempotency_key IS NOT NULL THEN
    IF receipt.actor_user_id=actor.actor_user_id AND receipt.org_id=actor.org_id AND receipt.command='create' AND receipt.request_fingerprint=fingerprint THEN
      RETURN QUERY SELECT 'ok',receipt.deadline_id,receipt.result_revision,true;
    ELSE RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::bigint,false; END IF; RETURN;
  END IF;
  PERFORM set_config('casechain.deadline_command','on',true);
  INSERT INTO public.deadlines(org_id,matter_id,type,due_date,description,title,legal_type,origin,verification_state,lifecycle,current_revision,created_by)
  VALUES(actor.org_id,p_matter_id,'other',p_due_date,p_obligation,p_title,p_legal_type,'manual','verified','open',1,actor.actor_user_id) RETURNING * INTO created;
  INSERT INTO public.deadline_versions(deadline_id,org_id,revision,title,obligation,legal_type,due_date,manual_basis,actor_user_id)
  VALUES(created.id,actor.org_id,1,p_title,p_obligation,p_legal_type,p_due_date,p_manual_basis,actor.actor_user_id);
  INSERT INTO public.deadline_command_receipts VALUES(p_idempotency_key,actor.org_id,actor.actor_user_id,'create',fingerprint,created.id,1,now());
  RETURN QUERY SELECT 'ok',created.id,1::bigint,false;
END $$;

CREATE FUNCTION public.amend_manual_legal_deadline(p_deadline_id uuid,p_expected_revision bigint,p_title text,p_obligation text,p_legal_type text,p_due_date date,p_manual_basis text,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,deadline_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.deadlines%ROWTYPE; actor record; receipt public.deadline_command_receipts%ROWTYPE; fingerprint text; next_revision bigint;
BEGIN
  p_title:=btrim(p_title); p_obligation:=btrim(p_obligation); p_manual_basis:=btrim(p_manual_basis); p_reason:=btrim(p_reason);
  IF p_deadline_id IS NULL OR p_title IS NULL OR p_obligation IS NULL OR p_manual_basis IS NULL OR p_reason IS NULL OR p_legal_type IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_due_date IS NULL OR p_idempotency_key IS NULL
    OR char_length(p_title) NOT BETWEEN 2 AND 160 OR p_title ~ '[[:cntrl:]]' OR char_length(p_obligation) NOT BETWEEN 2 AND 1000 OR p_obligation ~ '[[:cntrl:]]'
    OR char_length(p_manual_basis) NOT BETWEEN 2 AND 500 OR p_manual_basis ~ '[[:cntrl:]]' OR char_length(p_reason) NOT BETWEEN 2 AND 500 OR p_reason ~ '[[:cntrl:]]'
    OR p_legal_type NOT IN ('reply_due','appeal_due','payment_or_predeposit_due','compliance_due','stay_application_due','other_legal') THEN RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(d.matter_id,true);
  IF actor.actor_user_id IS NULL OR actor.org_id<>d.org_id THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('command','amend','deadline_id',p_deadline_id,'expected_revision',p_expected_revision,'title',p_title,'obligation',p_obligation,'legal_type',p_legal_type,'due_date',p_due_date,'manual_basis',p_manual_basis,'reason',p_reason));
  SELECT * INTO receipt FROM public.deadline_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.idempotency_key IS NOT NULL THEN IF receipt.actor_user_id=actor.actor_user_id AND receipt.org_id=actor.org_id AND receipt.command='amend' AND receipt.request_fingerprint=fingerprint THEN RETURN QUERY SELECT 'ok',receipt.deadline_id,receipt.result_revision,true; ELSE RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::bigint,false; END IF; RETURN; END IF;
  IF d.origin<>'manual' OR d.verification_state<>'verified' OR d.lifecycle<>'open' THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF d.current_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  next_revision:=d.current_revision+1; PERFORM set_config('casechain.deadline_command','on',true);
  UPDATE public.deadlines SET title=p_title,description=p_obligation,legal_type=p_legal_type,due_date=p_due_date,current_revision=next_revision,updated_at=now() WHERE id=d.id;
  INSERT INTO public.deadline_versions VALUES(d.id,d.org_id,next_revision,p_title,p_obligation,p_legal_type,p_due_date,p_manual_basis,p_reason,actor.actor_user_id,now());
  INSERT INTO public.deadline_command_receipts VALUES(p_idempotency_key,d.org_id,actor.actor_user_id,'amend',fingerprint,d.id,next_revision,now());
  RETURN QUERY SELECT 'ok',d.id,next_revision,false;
END $$;

CREATE FUNCTION public.record_manual_legal_deadline_outcome(p_deadline_id uuid,p_expected_revision bigint,p_outcome text,p_reason text,p_idempotency_key uuid)
RETURNS TABLE(code text,deadline_id uuid,revision bigint,replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE d public.deadlines%ROWTYPE; actor record; receipt public.deadline_command_receipts%ROWTYPE; fingerprint text; next_revision bigint; reason text:=nullif(btrim(p_reason),''); expected_command text:=CASE WHEN p_outcome='satisfied' THEN 'satisfy' ELSE 'cancel' END;
BEGIN
  IF p_deadline_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1 OR p_idempotency_key IS NULL OR p_outcome IS NULL OR p_outcome NOT IN ('satisfied','cancelled')
    OR (p_outcome='cancelled' AND (reason IS NULL OR char_length(reason) NOT BETWEEN 2 AND 500 OR reason ~ '[[:cntrl:]]'))
    OR (reason IS NOT NULL AND (char_length(reason) NOT BETWEEN 2 AND 500 OR reason ~ '[[:cntrl:]]')) THEN RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text,159));
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(d.matter_id,true);
  IF actor.actor_user_id IS NULL OR actor.org_id<>d.org_id THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  SELECT * INTO d FROM public.deadlines WHERE id=p_deadline_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  fingerprint:=public.deadline_fingerprint(jsonb_build_object('command',p_outcome,'deadline_id',p_deadline_id,'expected_revision',p_expected_revision,'reason',reason));
  SELECT * INTO receipt FROM public.deadline_command_receipts r WHERE r.idempotency_key=p_idempotency_key;
  IF receipt.idempotency_key IS NOT NULL THEN IF receipt.actor_user_id=actor.actor_user_id AND receipt.org_id=actor.org_id AND receipt.command=expected_command AND receipt.request_fingerprint=fingerprint THEN RETURN QUERY SELECT 'ok',receipt.deadline_id,receipt.result_revision,true; ELSE RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::bigint,false; END IF; RETURN; END IF;
  IF d.origin<>'manual' OR d.verification_state<>'verified' OR d.lifecycle<>'open' THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  IF d.current_revision<>p_expected_revision THEN RETURN QUERY SELECT 'stale_revision',NULL::uuid,NULL::bigint,false; RETURN; END IF;
  next_revision:=d.current_revision+1; PERFORM set_config('casechain.deadline_command','on',true);
  UPDATE public.deadlines SET lifecycle=p_outcome,is_resolved=true,resolved_by=actor.actor_user_id,resolved_at=now(),current_revision=next_revision,updated_at=now() WHERE id=d.id;
  INSERT INTO public.deadline_outcomes(deadline_id,org_id,revision,outcome,reason,actor_user_id) VALUES(d.id,d.org_id,next_revision,p_outcome,reason,actor.actor_user_id);
  INSERT INTO public.deadline_command_receipts VALUES(p_idempotency_key,d.org_id,actor.actor_user_id,expected_command,fingerprint,d.id,next_revision,now());
  RETURN QUERY SELECT 'ok',d.id,next_revision,false;
END $$;

CREATE FUNCTION public.read_matter_manual_legal_deadline_agenda(p_matter_id uuid,p_limit integer DEFAULT 50)
RETURNS TABLE(items jsonb,timezone text,as_of_date date,can_mutate boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; today date;
BEGIN
  IF p_matter_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN; END IF;
  SELECT * INTO actor FROM public.deadline_actor_for_matter(p_matter_id,false);
  IF actor.actor_user_id IS NULL THEN RETURN; END IF;
  today:=(clock_timestamp() AT TIME ZONE actor.timezone)::date;
  RETURN QUERY SELECT coalesce(jsonb_agg(item.obj ORDER BY item.rank,item.due_date,item.id),'[]'::jsonb),actor.timezone,today,actor.can_mutate FROM (
    SELECT d.id,d.due_date,
      CASE WHEN d.lifecycle='open' AND d.due_date<today THEN 0 WHEN d.lifecycle='open' THEN 1 ELSE 2 END rank,
      jsonb_build_object('id',d.id,'title',d.title,'obligation',d.description,'legal_type',d.legal_type,'due_date',d.due_date,'manual_basis',current_version.manual_basis,'origin','manual','verification_state','verified','lifecycle',d.lifecycle,'revision',d.current_revision,
        'temporal',CASE WHEN d.due_date<today THEN 'missed' WHEN d.due_date=today THEN 'due_today' WHEN d.due_date<=today+7 THEN 'due_soon' ELSE 'upcoming' END,
        'created_at',d.created_at,'updated_at',d.updated_at,'history',(
          SELECT jsonb_agg(h.obj ORDER BY h.at,h.revision) FROM (
            SELECT v.created_at at,v.revision,jsonb_build_object('kind',CASE WHEN v.revision=1 THEN 'created' ELSE 'amended' END,'revision',v.revision,'at',v.created_at,'actor_label',coalesce(nullif(btrim(profile.display_name),''),'Organisation member'),'title',v.title,'obligation',v.obligation,'legal_type',v.legal_type,'due_date',v.due_date,'manual_basis',v.manual_basis,'reason',v.amendment_reason) obj FROM public.deadline_versions v LEFT JOIN public.user_profiles profile ON profile.user_id=v.actor_user_id WHERE v.deadline_id=d.id
            UNION ALL SELECT o.recorded_at,o.revision,jsonb_build_object('kind',o.outcome,'revision',o.revision,'at',o.recorded_at,'actor_label',coalesce(nullif(btrim(profile.display_name),''),'Organisation member'),'reason',o.reason) FROM public.deadline_outcomes o LEFT JOIN public.user_profiles profile ON profile.user_id=o.actor_user_id WHERE o.deadline_id=d.id
          ) h
        )) obj
    FROM public.deadlines d JOIN LATERAL (
      SELECT version.manual_basis FROM public.deadline_versions version
      WHERE version.deadline_id=d.id AND version.org_id=d.org_id AND version.revision<=d.current_revision
      ORDER BY version.revision DESC LIMIT 1
    ) current_version ON true
    WHERE d.org_id=actor.org_id AND d.matter_id=p_matter_id AND d.origin='manual' AND d.verification_state='verified'
    ORDER BY rank,d.due_date,d.id LIMIT p_limit
  ) item;
END $$;

CREATE FUNCTION public.read_current_deadline_attention(p_limit integer DEFAULT 5)
RETURNS TABLE(items jsonb,timezone text,as_of_date date)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE member record; owner boolean; operational_timezone text; today date;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20 THEN RETURN; END IF;
  SELECT * INTO member FROM public.current_active_tenant_membership();
  IF member.membership_id IS NULL THEN RETURN; END IF;
  SELECT organisation.owner_membership_id=member.membership_id INTO owner FROM public.organisations organisation WHERE organisation.id=member.org_id;
  IF NOT ('document.view'=ANY(public.organisation_member_capabilities(member.role,coalesce(owner,false),'active'::public.organisation_membership_state))) THEN RETURN; END IF;
  SELECT settings.timezone INTO operational_timezone FROM public.organisation_operational_settings settings
  WHERE settings.org_id=member.org_id AND EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names zone WHERE zone.name=settings.timezone);
  IF operational_timezone IS NULL THEN RETURN; END IF;
  today:=(clock_timestamp() AT TIME ZONE operational_timezone)::date;
  RETURN QUERY SELECT coalesce(jsonb_agg(attention.item ORDER BY attention.due_date,attention.id),'[]'::jsonb),operational_timezone,today FROM (
    SELECT deadline.id,deadline.due_date,jsonb_build_object(
      'id',deadline.id,'due_date',deadline.due_date,'type',deadline.type::text,'description',deadline.description,
      'matter_title',matter.title,'client_name',client.name
    ) item
    FROM public.deadlines deadline
    JOIN public.matters matter ON matter.id=deadline.matter_id AND matter.org_id=deadline.org_id
      AND matter.record_state='active' AND matter.deleted_at IS NULL AND matter.work_state='active'
    JOIN public.clients client ON client.id=matter.client_id AND client.org_id=matter.org_id
      AND client.record_state='active' AND client.deleted_at IS NULL
    WHERE deadline.org_id=member.org_id AND deadline.verification_state='verified'
      AND deadline.lifecycle='open' AND NOT deadline.is_resolved
    ORDER BY deadline.due_date,deadline.id LIMIT p_limit
  ) attention;
END $$;

REVOKE ALL ON FUNCTION public.deadline_actor_for_matter(uuid,boolean),public.deadline_fingerprint(jsonb),public.create_manual_legal_deadline(uuid,text,text,text,date,text,uuid),public.amend_manual_legal_deadline(uuid,bigint,text,text,text,date,text,text,uuid),public.record_manual_legal_deadline_outcome(uuid,bigint,text,text,uuid),public.read_matter_manual_legal_deadline_agenda(uuid,integer),public.read_current_deadline_attention(integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_manual_legal_deadline(uuid,text,text,text,date,text,uuid),public.amend_manual_legal_deadline(uuid,bigint,text,text,text,date,text,text,uuid),public.record_manual_legal_deadline_outcome(uuid,bigint,text,text,uuid),public.read_matter_manual_legal_deadline_agenda(uuid,integer),public.read_current_deadline_attention(integer) TO authenticated;

COMMIT;
