-- D09-T04: strict source-observation candidates for client identifiers,
-- legal dates, actors, parties, money, and legal provisions. These candidates
-- remain inert: no identity, placement, relationship, effective, or outbox use.
BEGIN;

CREATE FUNCTION public.typed_material_observation_common_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT coalesce(jsonb_typeof(p_value)='object'
    AND jsonb_typeof(p_value->'raw')='string' AND char_length(p_value->>'raw') BETWEEN 1 AND 512
    AND p_value->>'raw'=btrim(p_value->>'raw') AND (p_value->>'raw') !~ '[[:cntrl:]]'
    AND jsonb_typeof(p_value->'display')='string' AND char_length(p_value->>'display') BETWEEN 1 AND 512
    AND p_value->>'display'=btrim(p_value->>'display') AND (p_value->>'display') !~ '[[:cntrl:]]'
    AND jsonb_typeof(p_value->'precision')='string' AND p_value->>'precision' IN ('exact','partial','unclear')
    AND jsonb_typeof(p_value->'catalogue_version')='string' AND (p_value->>'catalogue_version') ~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    AND jsonb_typeof(p_value->'normalizer_version')='string' AND (p_value->>'normalizer_version') ~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    AND jsonb_typeof(p_value->'normalization_state')='string' AND p_value->>'normalization_state' IN ('valid','provisional','invalid')
    AND jsonb_typeof(p_value->'validation_error') IN ('string','null')
    AND (jsonb_typeof(p_value->'validation_error')='null' OR ((p_value->>'validation_error') ~ '^[a-z][a-z0-9_]{0,63}$')),false)
$$;

CREATE FUNCTION public.typed_optional_source_text_is_valid(p_value jsonb,p_max integer)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT coalesce(jsonb_typeof(p_value)='null' OR (jsonb_typeof(p_value)='string' AND char_length(p_value#>>'{}') BETWEEN 1 AND p_max
    AND (p_value#>>'{}')=btrim(p_value#>>'{}') AND (p_value#>>'{}') !~ '[[:cntrl:]]'),false)
$$;

CREATE FUNCTION public.typed_gstin_checksum_is_valid(p_value text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE alphabet constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'; total integer := 0; digit integer; product integer;
BEGIN
  IF p_value !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$' THEN RETURN false; END IF;
  FOR i IN 1..14 LOOP
    digit := strpos(alphabet,substring(p_value,i,1))-1;
    product := digit * CASE WHEN i%2=1 THEN 1 ELSE 2 END;
    total := total + product/36 + product%36;
  END LOOP;
  RETURN substring(alphabet FROM ((36-total%36)%36)+1 FOR 1)=substring(p_value,15,1);
END $$;

CREATE FUNCTION public.typed_client_identifier_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE candidate text; syntax_valid boolean; exact boolean;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['catalogue_kind','catalogue_version','display','kind','normalization_state','normalized_value','normalizer_version','precision','raw','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'kind')<>'string' OR p_value->>'kind' NOT IN ('gstin','pan','tan','cin','other_catalogued')
    OR jsonb_typeof(p_value->'catalogue_kind') NOT IN ('string','null')
    OR (jsonb_typeof(p_value->'catalogue_kind')='string' AND p_value->>'catalogue_kind' NOT IN ('iec','udyam_registration','professional_tax_registration','other_registration'))
    OR ((p_value->>'kind'='other_catalogued') IS DISTINCT FROM (jsonb_typeof(p_value->'catalogue_kind')='string'))
    OR jsonb_typeof(p_value->'normalized_value') NOT IN ('string','null') THEN RETURN false; END IF;
  candidate:=upper(regexp_replace(replace(normalize(p_value->>'raw',NFKC),chr(65279),''),'[[:space:]./,_-]','','g'));
  syntax_valid:=CASE p_value->>'kind'
    WHEN 'gstin' THEN public.typed_gstin_checksum_is_valid(candidate)
    WHEN 'pan' THEN candidate ~ '^[A-Z]{5}[0-9]{4}[A-Z]$'
    WHEN 'tan' THEN candidate ~ '^[A-Z]{4}[0-9]{5}[A-Z]$'
    WHEN 'cin' THEN candidate ~ '^[LU][0-9]{5}[A-Z]{2}[0-9]{4}[A-Z]{3}[0-9]{6}$'
    ELSE char_length(candidate) BETWEEN 2 AND 128 AND candidate ~ '^[A-Z0-9]+$' END;
  exact:=p_value->>'precision'='exact';
  RETURN coalesce(p_value->>'normalized_value' IS NOT DISTINCT FROM CASE WHEN syntax_valid AND exact THEN candidate END
    AND p_value->>'normalization_state'=CASE WHEN NOT syntax_valid THEN 'invalid' WHEN exact THEN 'valid' ELSE 'provisional' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN NOT syntax_valid THEN 'invalid_'||(p_value->>'kind') WHEN NOT exact THEN 'identifier_not_exact' END,false);
END $$;

CREATE FUNCTION public.typed_legal_date_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE proposed text; supplied text; valid_date boolean; exact boolean;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['catalogue_version','display','meaning','normalization_state','normalized_date','normalizer_version','precision','proposed_normalized_date','raw','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'meaning')<>'string' OR p_value->>'meaning' NOT IN ('issue','filing','communication_service','order','hearing','due','source_unknown')
    OR NOT public.typed_optional_source_text_is_valid(p_value->'proposed_normalized_date',32)
    OR jsonb_typeof(p_value->'normalized_date') NOT IN ('string','null') THEN RETURN false; END IF;
  proposed:=p_value->>'proposed_normalized_date'; supplied:=p_value->>'normalized_date';
  valid_date:=proposed IS NOT NULL AND proposed ~ '^[1-9][0-9]{3}-[0-9]{2}-[0-9]{2}$' AND pg_input_is_valid(proposed,'date'); exact:=p_value->>'precision'='exact';
  RETURN coalesce(supplied IS NOT DISTINCT FROM CASE WHEN valid_date THEN proposed END
    AND p_value->>'normalization_state'=CASE WHEN proposed IS NULL THEN 'provisional' WHEN valid_date AND exact THEN 'valid' WHEN valid_date THEN 'provisional' ELSE 'invalid' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN proposed IS NULL OR (valid_date AND NOT exact) THEN 'date_not_exact' WHEN NOT valid_date THEN 'invalid_calendar_date' END,false);
END $$;

CREATE FUNCTION public.typed_actor_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE provisional boolean;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['actor_kind','authority','catalogue_version','display','jurisdiction','normalization_state','normalized','normalizer_version','office','precision','procedural_role','raw','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'actor_kind')<>'string' OR p_value->>'actor_kind' NOT IN ('issuer','recipient')
    OR jsonb_typeof(p_value->'procedural_role')<>'string' OR p_value->>'procedural_role' NOT IN ('authority','department','court','tribunal','taxpayer','appellant','respondent','petitioner','applicant','other','unknown')
    OR NOT public.typed_optional_source_text_is_valid(p_value->'authority',1024) OR NOT public.typed_optional_source_text_is_valid(p_value->'office',1024) OR NOT public.typed_optional_source_text_is_valid(p_value->'jurisdiction',1024)
    OR NOT public.jsonb_object_has_exact_keys(p_value->'normalized',ARRAY['authority','jurisdiction','office','procedural_role'])
    OR jsonb_typeof(p_value->'normalized'->'procedural_role')<>'string'
    OR jsonb_typeof(p_value->'normalized'->'authority') NOT IN ('string','null')
    OR jsonb_typeof(p_value->'normalized'->'office') NOT IN ('string','null')
    OR jsonb_typeof(p_value->'normalized'->'jurisdiction') NOT IN ('string','null')
    OR p_value->'normalized' IS DISTINCT FROM jsonb_build_object('procedural_role',p_value->'procedural_role','authority',p_value->'authority','office',p_value->'office','jurisdiction',p_value->'jurisdiction') THEN RETURN false; END IF;
  provisional:=p_value->>'procedural_role'='unknown' OR p_value->>'precision'<>'exact';
  RETURN coalesce(p_value->>'normalization_state'=CASE WHEN provisional THEN 'provisional' ELSE 'valid' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN p_value->>'procedural_role'='unknown' THEN 'unknown_actor_role' WHEN p_value->>'precision'<>'exact' THEN 'actor_not_exact' END,false);
END $$;

CREATE FUNCTION public.typed_party_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE provisional boolean;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['catalogue_version','display','normalization_state','normalized','normalizer_version','precision','procedural_role','raw','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'procedural_role')<>'string' OR p_value->>'procedural_role' NOT IN ('taxpayer','appellant','respondent','petitioner','applicant','authority','department','court','tribunal','intervenor','other','unknown')
    OR NOT public.jsonb_object_has_exact_keys(p_value->'normalized',ARRAY['name','procedural_role'])
    OR jsonb_typeof(p_value->'normalized'->'name')<>'string' OR jsonb_typeof(p_value->'normalized'->'procedural_role')<>'string'
    OR p_value->'normalized' IS DISTINCT FROM jsonb_build_object('name',p_value->'display','procedural_role',p_value->'procedural_role') THEN RETURN false; END IF;
  provisional:=p_value->>'procedural_role'='unknown' OR p_value->>'precision'<>'exact';
  RETURN coalesce(p_value->>'normalization_state'=CASE WHEN provisional THEN 'provisional' ELSE 'valid' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN p_value->>'procedural_role'='unknown' THEN 'unknown_party_role' WHEN p_value->>'precision'<>'exact' THEN 'party_not_exact' END,false);
END $$;

CREATE FUNCTION public.typed_money_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE amount_valid boolean; expected jsonb;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['amount','applicable_period_reference','catalogue_version','component','currency','display','legal_posture','normalization_state','normalized','normalizer_version','precision','raw','representation','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'representation')<>'string' OR p_value->>'representation' NOT IN ('decimal','integer_paise')
    OR jsonb_typeof(p_value->'amount')<>'string' OR char_length(p_value->>'amount')>256
    OR jsonb_typeof(p_value->'currency')<>'string' OR p_value->>'currency' !~ '^[A-Z]{3}$'
    OR jsonb_typeof(p_value->'component')<>'string' OR p_value->>'component' NOT IN ('tax','interest','penalty','fee','pre_deposit','total_demand','amount_in_dispute','amount_relief','other')
    OR NOT public.typed_optional_source_text_is_valid(p_value->'applicable_period_reference',512)
    OR jsonb_typeof(p_value->'legal_posture')<>'string' OR p_value->>'legal_posture' NOT IN ('alleged','demanded','confirmed','paid','refunded','disputed','relief','other','unknown')
    OR jsonb_typeof(p_value->'normalized') NOT IN ('object','null')
    OR (jsonb_typeof(p_value->'normalized')='object' AND (NOT public.jsonb_object_has_exact_keys(p_value->'normalized',ARRAY['applicable_period_reference','component','currency','legal_posture','representation','value'])
      OR jsonb_typeof(p_value->'normalized'->'representation')<>'string' OR jsonb_typeof(p_value->'normalized'->'value')<>'string'
      OR jsonb_typeof(p_value->'normalized'->'currency')<>'string' OR jsonb_typeof(p_value->'normalized'->'component')<>'string'
      OR jsonb_typeof(p_value->'normalized'->'applicable_period_reference') NOT IN ('string','null') OR jsonb_typeof(p_value->'normalized'->'legal_posture')<>'string')) THEN RETURN false; END IF;
  amount_valid:=char_length(p_value->>'amount')<=128 AND CASE WHEN p_value->>'representation'='decimal' THEN p_value->>'amount' ~ '^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$' ELSE p_value->>'amount' ~ '^(0|[1-9][0-9]*)$' END;
  expected:=CASE WHEN amount_valid THEN jsonb_build_object('representation',p_value->'representation','value',p_value->'amount','currency',p_value->'currency','component',p_value->'component','applicable_period_reference',p_value->'applicable_period_reference','legal_posture',p_value->'legal_posture') ELSE 'null'::jsonb END;
  RETURN coalesce(p_value->'normalized' IS NOT DISTINCT FROM expected
    AND p_value->>'normalization_state'=CASE WHEN NOT amount_valid THEN 'invalid' WHEN p_value->>'precision'='exact' THEN 'valid' ELSE 'provisional' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN NOT amount_valid THEN 'invalid_money_string' WHEN p_value->>'precision'<>'exact' THEN 'money_not_exact' END,false);
END $$;

CREATE FUNCTION public.typed_legal_provision_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE canonical text; components jsonb; valid boolean; expected jsonb;
BEGIN
  IF NOT public.jsonb_object_has_exact_keys(p_value,ARRAY['act','act_kind','catalogue_version','display','normalization_state','normalized','normalizer_version','precision','provision_kind','provision_value','raw','validation_error'])
    OR NOT public.typed_material_observation_common_is_valid(p_value)
    OR jsonb_typeof(p_value->'act_kind')<>'string' OR p_value->>'act_kind' NOT IN ('cgst_act','igst_act','gst_rules','constitution','other_catalogued','uncatalogued')
    OR NOT public.typed_optional_source_text_is_valid(p_value->'act',1024)
    OR jsonb_typeof(p_value->'provision_kind')<>'string' OR p_value->>'provision_kind' NOT IN ('section','rule','article','notification','circular','instruction','other')
    OR jsonb_typeof(p_value->'provision_value')<>'string' OR char_length(p_value->>'provision_value') NOT BETWEEN 1 AND 256
    OR p_value->>'provision_value'<>btrim(p_value->>'provision_value') OR (p_value->>'provision_value') ~ '[[:cntrl:]]'
    OR jsonb_typeof(p_value->'normalized') NOT IN ('object','null')
    OR (jsonb_typeof(p_value->'normalized')='object' AND (NOT public.jsonb_object_has_exact_keys(p_value->'normalized',ARRAY['act','act_kind','components','provision_kind','value'])
      OR jsonb_typeof(p_value->'normalized'->'act_kind')<>'string' OR jsonb_typeof(p_value->'normalized'->'act') NOT IN ('string','null')
      OR jsonb_typeof(p_value->'normalized'->'provision_kind')<>'string' OR jsonb_typeof(p_value->'normalized'->'value')<>'string'
      OR jsonb_typeof(p_value->'normalized'->'components')<>'array')) THEN RETURN false; END IF;
  canonical:=upper(regexp_replace(btrim(replace(normalize(p_value->>'provision_value',NFKC),chr(65279),' ')),'[[:space:]]+',' ','g'));
  canonical:=regexp_replace(canonical,'[[:space:]]*([/().:_-])[[:space:]]*','\1','g'); valid:=canonical ~ '[[:alnum:]]';
  SELECT coalesce(jsonb_agg(value),'[]'::jsonb) INTO components FROM regexp_split_to_table(canonical,'[/().:_-]+') value WHERE value<>'';
  expected:=CASE WHEN valid THEN jsonb_build_object('act_kind',p_value->'act_kind','act',p_value->'act','provision_kind',p_value->'provision_kind','value',canonical,'components',components) ELSE 'null'::jsonb END;
  RETURN coalesce(p_value->'normalized' IS NOT DISTINCT FROM expected
    AND p_value->>'normalization_state'=CASE WHEN NOT valid THEN 'invalid' WHEN p_value->>'act_kind'='uncatalogued' OR p_value->>'precision'<>'exact' THEN 'provisional' ELSE 'valid' END
    AND p_value->>'validation_error' IS NOT DISTINCT FROM CASE WHEN NOT valid THEN 'invalid_legal_provision' WHEN p_value->>'act_kind'='uncatalogued' THEN 'uncatalogued_act' WHEN p_value->>'precision'<>'exact' THEN 'provision_not_exact' END,false);
END $$;

CREATE FUNCTION public.typed_material_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog,public AS $$
  SELECT coalesce(public.typed_client_identifier_candidate_is_valid(p_value)
    OR public.typed_legal_date_candidate_is_valid(p_value)
    OR public.typed_actor_candidate_is_valid(p_value)
    OR public.typed_party_candidate_is_valid(p_value)
    OR public.typed_money_candidate_is_valid(p_value)
    OR public.typed_legal_provision_candidate_is_valid(p_value),false)
$$;

CREATE OR REPLACE FUNCTION public.source_field_candidate_normalized_value_is_valid(p_value_type public.source_field_candidate_value_type,p_value jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE value_text text;
BEGIN
  IF p_value IS NULL THEN RETURN false; END IF;
  IF p_value_type='structured' THEN RETURN public.typed_tax_period_candidate_is_valid(p_value) OR public.typed_official_reference_candidate_is_valid(p_value) OR public.typed_material_candidate_is_valid(p_value); END IF;
  IF p_value_type='boolean' THEN RETURN jsonb_typeof(p_value)='boolean'; END IF;
  IF jsonb_typeof(p_value)<>'string' THEN RETURN false; END IF; value_text:=p_value#>>'{}';
  IF p_value_type='text' THEN RETURN char_length(value_text) BETWEEN 1 AND 1024 AND value_text !~ '[[:cntrl:]]';
  ELSIF p_value_type='code' THEN RETURN value_text ~ '^[A-Za-z0-9][A-Za-z0-9 .,/()&+#:_-]{0,255}$';
  ELSIF p_value_type='date' THEN RETURN value_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND pg_input_is_valid(value_text,'date');
  ELSIF p_value_type='integer' THEN RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})$';
  ELSIF p_value_type='decimal' THEN RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$'; END IF;
  RETURN false;
END $$;

ALTER TABLE public.source_field_candidates DROP CONSTRAINT source_field_candidates_structured_path_valid;
ALTER TABLE public.source_field_candidates ADD CONSTRAINT source_field_candidates_structured_path_valid CHECK (
  (value_type='structured' AND (
    (field_path='document.tax_period' AND public.typed_tax_period_candidate_is_valid(normalized_value))
    OR (field_path IN ('document.official_reference.self_identifier','document.official_reference.outbound_mention') AND public.typed_official_reference_candidate_is_valid(normalized_value) AND normalized_value->>'role'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.client_identifier.%' AND public.typed_client_identifier_candidate_is_valid(normalized_value) AND normalized_value->>'kind'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.legal_date.%' AND public.typed_legal_date_candidate_is_valid(normalized_value) AND normalized_value->>'meaning'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.actor.%' AND public.typed_actor_candidate_is_valid(normalized_value) AND normalized_value->>'actor_kind'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.party.%' AND public.typed_party_candidate_is_valid(normalized_value) AND normalized_value->>'procedural_role'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.money.%' AND public.typed_money_candidate_is_valid(normalized_value) AND normalized_value->>'component'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.legal_provision.%' AND public.typed_legal_provision_candidate_is_valid(normalized_value) AND normalized_value->>'provision_kind'=split_part(field_path,'.',3))))
  OR (value_type<>'structured' AND field_path NOT LIKE 'document.client_identifier.%' AND field_path NOT LIKE 'document.legal_date.%'
    AND field_path NOT LIKE 'document.actor.%' AND field_path NOT LIKE 'document.party.%' AND field_path NOT LIKE 'document.money.%'
    AND field_path NOT LIKE 'document.legal_provision.%' AND field_path NOT IN ('document.tax_period','document.official_reference.self_identifier','document.official_reference.outbound_mention'))
);
ALTER TABLE public.source_field_candidates ADD CONSTRAINT source_field_candidates_material_state_valid CHECK (
  value_type<>'structured' OR NOT public.typed_material_candidate_is_valid(normalized_value)
  OR (normalized_value->>'normalization_state'='invalid' AND validation_state='invalid')
  OR (normalized_value->>'normalization_state'='provisional' AND validation_state IN ('provisional','invalid'))
  OR (normalized_value->>'normalization_state'='valid' AND validation_state IN ('provisional','invalid'))
);

ALTER TABLE public.document_field_candidates DROP CONSTRAINT document_field_candidates_structured_path_valid;
ALTER TABLE public.document_field_candidates ADD CONSTRAINT document_field_candidates_structured_path_valid CHECK (
  (value_type='structured' AND (
    (field_path='document.tax_period' AND public.typed_tax_period_candidate_is_valid(normalized_value))
    OR (field_path IN ('document.official_reference.self_identifier','document.official_reference.outbound_mention') AND public.typed_official_reference_candidate_is_valid(normalized_value) AND normalized_value->>'role'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.client_identifier.%' AND public.typed_client_identifier_candidate_is_valid(normalized_value) AND normalized_value->>'kind'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.legal_date.%' AND public.typed_legal_date_candidate_is_valid(normalized_value) AND normalized_value->>'meaning'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.actor.%' AND public.typed_actor_candidate_is_valid(normalized_value) AND normalized_value->>'actor_kind'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.party.%' AND public.typed_party_candidate_is_valid(normalized_value) AND normalized_value->>'procedural_role'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.money.%' AND public.typed_money_candidate_is_valid(normalized_value) AND normalized_value->>'component'=split_part(field_path,'.',3))
    OR (field_path LIKE 'document.legal_provision.%' AND public.typed_legal_provision_candidate_is_valid(normalized_value) AND normalized_value->>'provision_kind'=split_part(field_path,'.',3))))
  OR (value_type<>'structured' AND field_path NOT LIKE 'document.client_identifier.%' AND field_path NOT LIKE 'document.legal_date.%'
    AND field_path NOT LIKE 'document.actor.%' AND field_path NOT LIKE 'document.party.%' AND field_path NOT LIKE 'document.money.%'
    AND field_path NOT LIKE 'document.legal_provision.%' AND field_path NOT IN ('document.tax_period','document.official_reference.self_identifier','document.official_reference.outbound_mention'))
);
ALTER TABLE public.document_field_candidates ADD CONSTRAINT document_field_candidates_material_state_valid CHECK (
  value_type<>'structured' OR NOT public.typed_material_candidate_is_valid(normalized_value)
  OR (normalized_value->>'normalization_state'='invalid' AND validation_state='invalid')
  OR (normalized_value->>'normalization_state'='provisional' AND validation_state IN ('provisional','invalid'))
  OR (normalized_value->>'normalization_state'='valid' AND validation_state IN ('provisional','invalid'))
);

CREATE OR REPLACE FUNCTION public.source_field_candidate_value_match_count(p_value_type public.source_field_candidate_value_type,p_normalized_value jsonb,p_source_text text)
RETURNS integer LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE source_text text:=replace(p_source_text,chr(65279),' ');
BEGIN
  IF p_value_type='structured' AND public.typed_official_reference_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count('code',to_jsonb(p_normalized_value->>'normalized_value'),source_text);
  ELSIF p_value_type='structured' AND public.typed_tax_period_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count('text',to_jsonb(p_normalized_value->>'raw'),source_text);
  ELSIF p_value_type='structured' AND public.typed_legal_date_candidate_is_valid(p_normalized_value) AND p_normalized_value->>'normalized_date' IS NOT NULL THEN
    RETURN public.source_field_candidate_value_match_count('date',to_jsonb(p_normalized_value->>'normalized_date'),source_text);
  ELSIF p_value_type='structured' AND public.typed_client_identifier_candidate_is_valid(p_normalized_value) AND p_normalized_value->>'normalized_value' IS NOT NULL THEN
    RETURN public.source_field_candidate_value_match_count('code',to_jsonb(p_normalized_value->>'normalized_value'),source_text);
  ELSIF p_value_type='structured' AND public.typed_money_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count_legacy('decimal',to_jsonb(p_normalized_value->>'amount'),source_text);
  ELSIF p_value_type='structured' AND public.typed_actor_candidate_is_valid(p_normalized_value) THEN
    IF public.source_field_candidate_value_match_count_legacy('text',to_jsonb(p_normalized_value->>'raw'),source_text)<>1
      OR (p_normalized_value->>'authority' IS NOT NULL AND position(upper(normalize(p_normalized_value->>'authority',NFKC)) IN upper(normalize(source_text,NFKC)))=0)
      OR (p_normalized_value->>'office' IS NOT NULL AND position(upper(normalize(p_normalized_value->>'office',NFKC)) IN upper(normalize(source_text,NFKC)))=0)
      OR (p_normalized_value->>'jurisdiction' IS NOT NULL AND position(upper(normalize(p_normalized_value->>'jurisdiction',NFKC)) IN upper(normalize(source_text,NFKC)))=0) THEN RETURN 0; END IF;
    RETURN 1;
  ELSIF p_value_type='structured' AND public.typed_legal_provision_candidate_is_valid(p_normalized_value) THEN
    IF p_normalized_value->>'normalization_state'='invalid' THEN
      RETURN public.source_field_candidate_value_match_count_legacy('text',to_jsonb(p_normalized_value->>'raw'),source_text);
    END IF;
    RETURN public.source_field_candidate_value_match_count_legacy('code',to_jsonb(p_normalized_value->'normalized'->>'value'),source_text);
  ELSIF p_value_type='structured' AND public.typed_material_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count_legacy('text',to_jsonb(p_normalized_value->>'raw'),source_text);
  END IF;
  RETURN public.source_field_candidate_value_match_count_legacy(p_value_type,p_normalized_value,source_text);
END $$;

CREATE OR REPLACE FUNCTION public.source_field_candidate_value_resolves_in_text(
  p_value_type public.source_field_candidate_value_type,p_normalized_value jsonb,p_source_text text
) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public AS $$
DECLARE candidate text;
BEGIN
  IF p_source_text IS NULL THEN RETURN false; END IF;
  IF p_value_type='boolean' THEN
    IF jsonb_typeof(p_normalized_value)<>'string' THEN RETURN false; END IF;
    candidate:=p_normalized_value#>>'{}';
    RETURN position(upper(candidate) IN upper(p_source_text))>0;
  END IF;
  RETURN public.source_field_candidate_value_match_count(p_value_type,p_normalized_value,p_source_text)=1;
END $$;

REVOKE ALL ON FUNCTION public.typed_material_observation_common_is_valid(jsonb),public.typed_optional_source_text_is_valid(jsonb,integer),public.typed_gstin_checksum_is_valid(text),
  public.typed_client_identifier_candidate_is_valid(jsonb),public.typed_legal_date_candidate_is_valid(jsonb),public.typed_actor_candidate_is_valid(jsonb),
  public.typed_party_candidate_is_valid(jsonb),public.typed_money_candidate_is_valid(jsonb),public.typed_legal_provision_candidate_is_valid(jsonb),
  public.typed_material_candidate_is_valid(jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_value_resolves_in_text(public.source_field_candidate_value_type,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the audited 00117 finisher and wrap it so a source-derived unknown
-- direction remains SQL NULL instead of being silently rewritten as incoming.
ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  RENAME TO finish_document_processing_ai_extraction_v3;

CREATE FUNCTION public.finish_document_processing_ai_extraction(
  p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,p_source_analysis_lease_token uuid,
  p_outcome text,p_input_tokens bigint,p_output_tokens bigint,p_latency_ms integer,
  p_candidates jsonb DEFAULT '[]'::jsonb,p_review_required boolean DEFAULT false,p_legacy_metadata jsonb DEFAULT NULL
) RETURNS TABLE(code text,binding_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE finished record; source_schema_version text; candidate jsonb;
DECLARE issuer_group_count integer; recipient_group_count integer; issuer_group text; recipient_group text; derived_direction text;
BEGIN
  SELECT schema_version INTO source_schema_version FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id;
  IF source_schema_version='document-extraction-v4' THEN
    IF p_candidates IS NULL OR jsonb_typeof(p_candidates)<>'array' OR jsonb_array_length(p_candidates)>1000 THEN
      RAISE EXCEPTION 'v4 candidates must be a bounded JSON array';
    END IF;
    FOR candidate IN SELECT value FROM jsonb_array_elements(p_candidates) LOOP
      IF jsonb_typeof(candidate)<>'object' OR NOT public.jsonb_object_has_exact_keys(candidate,ARRAY[
        'confidence','evidence_regions','field_path','normalized_value','page_number','quotation','semantic_candidate_key',
        'validation_error_codes','validation_state','value_type','verified_source_anchor'
      ]) THEN RAISE EXCEPTION 'v4 candidate envelope has missing or unknown keys'; END IF;
    END LOOP;
  END IF;
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction_v3(
    p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,
    p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required,p_legacy_metadata);
  IF finished.code IN ('validated','review_required') AND source_schema_version='document-extraction-v4' THEN
    WITH actor_groups AS (
      SELECT normalized_value->>'actor_kind' actor_kind,
        CASE WHEN normalized_value->>'procedural_role' IN ('authority','department','court','tribunal') THEN 'official'
          WHEN normalized_value->>'procedural_role' IN ('taxpayer','appellant','respondent','petitioner','applicant') THEN 'private'
          ELSE 'unknown' END side_group
      FROM public.source_field_candidates
      WHERE source_analysis_run_id=p_source_analysis_run_id AND value_type='structured' AND validation_state<>'invalid'
        AND public.typed_actor_candidate_is_valid(normalized_value)
    )
    SELECT count(DISTINCT side_group) FILTER (WHERE actor_kind='issuer'),count(DISTINCT side_group) FILTER (WHERE actor_kind='recipient'),
      min(side_group) FILTER (WHERE actor_kind='issuer'),min(side_group) FILTER (WHERE actor_kind='recipient')
    INTO issuer_group_count,recipient_group_count,issuer_group,recipient_group FROM actor_groups;
    derived_direction:=CASE
      WHEN issuer_group_count=1 AND recipient_group_count=1 AND issuer_group='official' AND recipient_group='private' THEN 'incoming'
      WHEN issuer_group_count=1 AND recipient_group_count=1 AND issuer_group='private' AND recipient_group='official' THEN 'outgoing'
      ELSE NULL END;
    UPDATE public.documents document_row SET direction=derived_direction::public.doc_direction
    FROM public.document_processing_runs processing_run
    WHERE processing_run.id=p_processing_run_id AND processing_run.document_id=document_row.id
      AND processing_run.org_id=document_row.org_id AND document_row.current_version_id=processing_run.document_version_id;
  END IF;
  RETURN QUERY SELECT finished.code::text,finished.binding_id::uuid;
END $$;

REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction_v3(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;

COMMIT;
