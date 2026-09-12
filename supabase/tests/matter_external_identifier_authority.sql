-- Run after migration 00147 on the disposable local database. The fixture is
-- rollback-only and exercises the governed identifier and purge boundaries.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000001','authenticated','authenticated','owner@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000002','authenticated','authenticated','admin@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000003','authenticated','authenticated','associate@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000004','authenticated','authenticated','viewer@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000005','authenticated','authenticated','suspended@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000006','authenticated','authenticated','foreign@identifier.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1470000-0000-0000-0000-000000000007','authenticated','authenticated','ambiguous@identifier.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('b1470000-0000-0000-0000-000000000001','Identifier organisation','a1470000-0000-0000-0000-000000000001'),
  ('b1470000-0000-0000-0000-000000000002','Foreign identifier organisation','a1470000-0000-0000-0000-000000000006'),
  ('b1470000-0000-0000-0000-000000000003','Ambiguous identifier organisation','a1470000-0000-0000-0000-000000000007');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000002','admin'),
  ('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000003','associate'),
  ('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000004','viewer'),
  ('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000005','associate');
UPDATE public.organisation_memberships
SET state='suspended',suspended_at=now(),suspended_by='a1470000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='b1470000-0000-0000-0000-000000000001' AND user_id='a1470000-0000-0000-0000-000000000005';

-- Simulate legacy/corrupt ambiguous current authority inside this rollback-only
-- transaction. Production keeps the global unique index; the command must also
-- fail closed if that invariant is ever violated.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
VALUES('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000007','associate','active',1,'a1470000-0000-0000-0000-000000000001');

INSERT INTO public.clients(id,org_id,name) VALUES
  ('c1470000-0000-0000-0000-000000000001','b1470000-0000-0000-0000-000000000001','Identifier client A'),
  ('c1470000-0000-0000-0000-000000000002','b1470000-0000-0000-0000-000000000001','Identifier client B'),
  ('c1470000-0000-0000-0000-000000000003','b1470000-0000-0000-0000-000000000001','Identifier purge client'),
  ('c1470000-0000-0000-0000-000000000004','b1470000-0000-0000-0000-000000000002','Foreign identifier client');
INSERT INTO public.matters(id,org_id,client_id,title,financial_year,matter_code,status) VALUES
  ('d1470000-0000-0000-0000-000000000001','b1470000-0000-0000-0000-000000000001','c1470000-0000-0000-0000-000000000001','Identifier matter A','2026-27','IDENT-147-A','active'),
  ('d1470000-0000-0000-0000-000000000002','b1470000-0000-0000-0000-000000000001','c1470000-0000-0000-0000-000000000002','Identifier matter B','2026-27','IDENT-147-B','active'),
  ('d1470000-0000-0000-0000-000000000003','b1470000-0000-0000-0000-000000000001','c1470000-0000-0000-0000-000000000003','Identifier purge matter','2026-27','PURGE-147','active'),
  ('d1470000-0000-0000-0000-000000000004','b1470000-0000-0000-0000-000000000002','c1470000-0000-0000-0000-000000000004','Foreign identifier matter','2026-27','FOREIGN-147','active');

INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by) VALUES
  ('e1470000-0000-0000-0000-000000000001','b1470000-0000-0000-0000-000000000001','d1470000-0000-0000-0000-000000000001','fixture/identifier-a.pdf','Identifier source A','proceeding','upload','source_attached','placed','a1470000-0000-0000-0000-000000000001'),
  ('e1470000-0000-0000-0000-000000000002','b1470000-0000-0000-0000-000000000001','d1470000-0000-0000-0000-000000000002','fixture/identifier-b.pdf','Identifier source B','proceeding','upload','source_attached','placed','a1470000-0000-0000-0000-000000000001'),
  ('e1470000-0000-0000-0000-000000000003','b1470000-0000-0000-0000-000000000001','d1470000-0000-0000-0000-000000000003','fixture/identifier-purge.pdf','Identifier purge source','proceeding','upload','source_attached','placed','a1470000-0000-0000-0000-000000000001'),
  ('e1470000-0000-0000-0000-000000000004','b1470000-0000-0000-0000-000000000002','d1470000-0000-0000-0000-000000000004','fixture/identifier-foreign.pdf','Foreign identifier source','proceeding','upload','source_attached','placed','a1470000-0000-0000-0000-000000000006');
INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
  ('f1470000-0000-0000-0000-000000000001','b1470000-0000-0000-0000-000000000001','documents','orgs/b1470000-0000-0000-0000-000000000001/assets/f1470000-0000-0000-0000-000000000001/original.pdf',repeat('1',64),100,'application/pdf','available',now(),2,'a1470000-0000-0000-0000-000000000001'),
  ('f1470000-0000-0000-0000-000000000002','b1470000-0000-0000-0000-000000000001','documents','orgs/b1470000-0000-0000-0000-000000000001/assets/f1470000-0000-0000-0000-000000000002/original.pdf',repeat('2',64),100,'application/pdf','available',now(),2,'a1470000-0000-0000-0000-000000000001'),
  ('f1470000-0000-0000-0000-000000000003','b1470000-0000-0000-0000-000000000001','documents','orgs/b1470000-0000-0000-0000-000000000001/assets/f1470000-0000-0000-0000-000000000003/original.pdf',repeat('3',64),100,'application/pdf','available',now(),2,'a1470000-0000-0000-0000-000000000001'),
  ('f1470000-0000-0000-0000-000000000004','b1470000-0000-0000-0000-000000000002','documents','orgs/b1470000-0000-0000-0000-000000000002/assets/f1470000-0000-0000-0000-000000000004/original.pdf',repeat('4',64),100,'application/pdf','available',now(),2,'a1470000-0000-0000-0000-000000000006');
INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
  ('01470000-0000-0000-0000-000000000001','b1470000-0000-0000-0000-000000000001','e1470000-0000-0000-0000-000000000001','f1470000-0000-0000-0000-000000000001',1,'identifier-a.pdf',2,'valid','current',now(),now(),'a1470000-0000-0000-0000-000000000001'),
  ('01470000-0000-0000-0000-000000000002','b1470000-0000-0000-0000-000000000001','e1470000-0000-0000-0000-000000000002','f1470000-0000-0000-0000-000000000002',1,'identifier-b.pdf',2,'valid','current',now(),now(),'a1470000-0000-0000-0000-000000000001'),
  ('01470000-0000-0000-0000-000000000003','b1470000-0000-0000-0000-000000000001','e1470000-0000-0000-0000-000000000003','f1470000-0000-0000-0000-000000000003',1,'identifier-purge.pdf',2,'valid','current',now(),now(),'a1470000-0000-0000-0000-000000000001'),
  ('01470000-0000-0000-0000-000000000004','b1470000-0000-0000-0000-000000000002','e1470000-0000-0000-0000-000000000004','f1470000-0000-0000-0000-000000000004',1,'identifier-foreign.pdf',2,'valid','current',now(),now(),'a1470000-0000-0000-0000-000000000006');
UPDATE public.documents SET current_version_id=CASE id
  WHEN 'e1470000-0000-0000-0000-000000000001' THEN '01470000-0000-0000-0000-000000000001'::uuid
  WHEN 'e1470000-0000-0000-0000-000000000002' THEN '01470000-0000-0000-0000-000000000002'::uuid
  WHEN 'e1470000-0000-0000-0000-000000000003' THEN '01470000-0000-0000-0000-000000000003'::uuid
  ELSE '01470000-0000-0000-0000-000000000004'::uuid END
WHERE id IN (
  'e1470000-0000-0000-0000-000000000001','e1470000-0000-0000-0000-000000000002',
  'e1470000-0000-0000-0000-000000000003','e1470000-0000-0000-0000-000000000004'
);

DO $catalogue_and_normalizer$
DECLARE a text; b text; c text; components jsonb; denied boolean:=false;
BEGIN
  IF (SELECT count(*) FROM public.matter_identifier_kind_catalogue WHERE catalogue_version=1)<>6
     OR (SELECT count(*) FROM public.matter_identifier_kind_catalogue WHERE identity_eligible AND NOT suggestion_only)<>5
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifier_kind_catalogue WHERE identifier_kind='other_official_reference' AND suggestion_only AND NOT identity_eligible)
     OR to_regclass('public.idx_matters_unique_client_fy') IS NULL
     OR to_regclass('public.matters_org_matter_code_unique') IS NULL THEN
    RAISE EXCEPTION 'catalogue or retained Matter uniqueness contract failed';
  END IF;
  SELECT normalized_value,normalized_components INTO a,components FROM public.normalize_matter_identifier_value_v1('proceeding_case_id',' gst / 001 / 2026 ');
  SELECT normalized_value INTO b FROM public.normalize_matter_identifier_value_v1('proceeding_case_id','GST/001/2026');
  SELECT normalized_value INTO c FROM public.normalize_matter_identifier_value_v1('proceeding_case_id','GST-001-2026');
  IF a<>'GST/001/2026' OR b<>a OR c=a OR components->>'numericCore'<>'001'
     OR (SELECT normalized_value FROM public.normalize_matter_identifier_value_v1('proceeding_case_id','GST/1/2026'))=a
     OR (SELECT normalized_value FROM public.normalize_matter_identifier_value_v1('proceeding_case_id',U&'GST\2013A'))<>'GST-A' THEN
    RAISE EXCEPTION 'conservative normalization or near-collision contract failed';
  END IF;
  BEGIN UPDATE public.matter_identifier_kind_catalogue SET suggestion_only=true WHERE identifier_kind='notice_reference'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'versioned kind catalogue was mutable'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.matter_identifier_normalizer_catalogue WHERE normalizer_key='official_reference_conservative'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'versioned normalizer catalogue was mutable'; END IF;
END $catalogue_and_normalizer$;

DO $acl$
BEGIN
  IF has_table_privilege('authenticated','public.matter_identifiers','SELECT')
     OR has_table_privilege('service_role','public.matter_identifiers','INSERT')
     OR has_table_privilege('service_role','public.matter_identifier_decisions','UPDATE')
     OR has_function_privilege('anon','public.activate_matter_identifier(uuid,bigint,public.matter_identifier_kind,public.matter_identifier_role,text,text,text,uuid,uuid,integer,text,jsonb,text,uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_matter_identifiers(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_matter_identifiers(uuid)','EXECUTE')
     OR NOT ('matter.identifier.manage'=ANY(public.organisation_member_capabilities('associate',false,'active')))
     OR 'matter.identifier.manage'=ANY(public.organisation_member_capabilities('viewer',false,'active'))
     OR cardinality(public.organisation_member_capabilities('associate',false,'suspended'))<>0 THEN
    RAISE EXCEPTION 'identifier ACL or capability contract failed';
  END IF;
END $acl$;

-- Suggestions and outbound mentions are non-authoritative and never reserve.
INSERT INTO public.matter_identifiers(
  org_id,client_id,matter_id,identifier_kind,identifier_role,catalogue_version,
  normalizer_key,normalizer_version,identity_eligible,issuer_namespace_raw,
  issuer_namespace_display,issuer_namespace_normalized,raw_value,display_value,
  normalized_value,normalized_components,verification_method
)
SELECT 'b1470000-0000-0000-0000-000000000001','c1470000-0000-0000-0000-000000000001','d1470000-0000-0000-0000-000000000001',
  'proceeding_case_id','outbound_mention',1,'official_reference_conservative',1,true,
  'GST Tribunal','GST Tribunal',public.normalize_matter_identifier_namespace_v1('GST Tribunal'),
  'SUG/1/2026','SUG/1/2026',normalized_value,normalized_components,'unverified_suggestion'
FROM public.normalize_matter_identifier_value_v1('proceeding_case_id','SUG/1/2026');
INSERT INTO public.matter_identifiers(
  org_id,client_id,matter_id,identifier_kind,identifier_role,catalogue_version,
  normalizer_key,normalizer_version,identity_eligible,issuer_namespace_raw,
  issuer_namespace_display,issuer_namespace_normalized,raw_value,display_value,
  normalized_value,normalized_components,verification_method
)
SELECT fixture.org_id,fixture.client_id,fixture.matter_id,
  'other_official_reference','outbound_mention',1,'official_reference_conservative',1,false,
  'Other Authority','Other Authority',public.normalize_matter_identifier_namespace_v1('Other Authority'),
  'OTHER/SHARED/2026','OTHER/SHARED/2026',normalized.normalized_value,
  normalized.normalized_components,'unverified_suggestion'
FROM (VALUES
  ('b1470000-0000-0000-0000-000000000001'::uuid,'c1470000-0000-0000-0000-000000000001'::uuid,'d1470000-0000-0000-0000-000000000001'::uuid),
  ('b1470000-0000-0000-0000-000000000001'::uuid,'c1470000-0000-0000-0000-000000000002'::uuid,'d1470000-0000-0000-0000-000000000002'::uuid)
) AS fixture(org_id,client_id,matter_id)
CROSS JOIN LATERAL public.normalize_matter_identifier_value_v1('other_official_reference','OTHER/SHARED/2026') AS normalized;
INSERT INTO public.matter_identifiers(
  org_id,client_id,matter_id,identifier_kind,identifier_role,catalogue_version,
  normalizer_key,normalizer_version,identity_eligible,issuer_namespace_raw,
  issuer_namespace_display,issuer_namespace_normalized,raw_value,display_value,
  normalized_value,normalized_components,verification_method
)
SELECT 'b1470000-0000-0000-0000-000000000001','c1470000-0000-0000-0000-000000000002','d1470000-0000-0000-0000-000000000002',
  'proceeding_case_id','outbound_mention',1,'official_reference_conservative',1,true,
  'GST Tribunal','GST Tribunal',public.normalize_matter_identifier_namespace_v1('GST Tribunal'),
  'SUG/1/2026','SUG/1/2026',normalized_value,normalized_components,'unverified_suggestion'
FROM public.normalize_matter_identifier_value_v1('proceeding_case_id','SUG/1/2026');

SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','a1470000-0000-0000-0000-000000000001','iat',extract(epoch FROM now())::bigint)::text,true);

DO $owner_activate$
DECLARE result record; matter_revision bigint;
BEGIN
  SELECT revision INTO matter_revision FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.activate_matter_identifier(
    'd1470000-0000-0000-0000-000000000001',matter_revision,'proceeding_case_id','self_identifier',
    ' GST Tribunal ',' gst / 001 / 2026 ','GST/001/2026',
    'e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,
    'Proceeding reference GST / 001 / 2026','[{"x":0.1,"y":0.1,"width":0.2,"height":0.1}]',
    'Verified from source','14700000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR result.identifier_id IS NULL OR result.identifier_revision<>1 OR result.replayed THEN
    RAISE EXCEPTION 'Owner identifier activation failed: %',result.code;
  END IF;
  PERFORM set_config('test.identifier.owner',result.identifier_id::text,true);
  PERFORM set_config('test.matter.a.revision',result.matter_revision::text,true);
  IF NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=result.identifier_id
    AND raw_value=' gst / 001 / 2026 ' AND issuer_namespace_raw=' GST Tribunal '
    AND normalized_value='GST/001/2026' AND evidence_quote='Proceeding reference GST / 001 / 2026'
    AND evidence_document_version_id='01470000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'raw/display/evidence lineage was not retained';
  END IF;
END $owner_activate$;

SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000002',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','a1470000-0000-0000-0000-000000000002','iat',extract(epoch FROM now())::bigint)::text,true);
DO $admin_alias$
DECLARE result record; matter_revision bigint;
BEGIN
  SELECT revision INTO matter_revision FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.activate_matter_identifier(
    'd1470000-0000-0000-0000-000000000001',matter_revision,'notice_reference','self_identifier',
    'CBIC','SCN/55/2026','SCN/55/2026','e1470000-0000-0000-0000-000000000001',
    '01470000-0000-0000-0000-000000000001',2,'Notice SCN/55/2026','[]','Alias verified',
    '14700000-0000-0000-0000-000000000002');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Admin alias activation failed: %',result.code; END IF;
END $admin_alias$;

SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000003',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','a1470000-0000-0000-0000-000000000003','iat',extract(epoch FROM now())::bigint)::text,true);
DO $associate_activate$
DECLARE result record; matter_revision bigint;
BEGIN
  SELECT revision INTO matter_revision FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO result FROM public.activate_matter_identifier(
    'd1470000-0000-0000-0000-000000000002',matter_revision,'order_reference','self_identifier',
    'GST Tribunal','ORD/88/2026','ORD/88/2026','e1470000-0000-0000-0000-000000000002',
    '01470000-0000-0000-0000-000000000002',1,'Order ORD/88/2026','[]',NULL,
    '14700000-0000-0000-0000-000000000003');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'Associate activation failed: %',result.code; END IF;
END $associate_activate$;

DO $failure_matrix$
DECLARE result record; rev bigint; identifier_count integer; decision_count integer; activity_count integer; receipt_count integer;
BEGIN
  SELECT count(*) INTO identifier_count FROM public.matter_identifiers;
  SELECT count(*) INTO decision_count FROM public.matter_identifier_decisions;
  SELECT count(*) INTO activity_count FROM public.activity_events WHERE event_type='matter.identifier_changed';
  SELECT count(*) INTO receipt_count FROM public.matter_identifier_command_receipts;
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'proceeding_case_id','self_identifier','GST Tribunal','GST/001/2026','duplicate','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'GST/001/2026','[]',NULL,'14700000-0000-0000-0000-000000000011');
  IF result.code<>'duplicate_active' THEN RAISE EXCEPTION 'same-Matter duplicate not rejected: %',result.code; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'other_official_reference','self_identifier','GST Tribunal','OTHER/1','other','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'OTHER/1','[]',NULL,'14700000-0000-0000-0000-000000000012');
  IF result.code<>'suggestion_only' THEN RAISE EXCEPTION 'suggestion-only kind gained identity authority'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'appeal_reference','outbound_mention','GST Tribunal','APL/1','appeal','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'APL/1','[]',NULL,'14700000-0000-0000-0000-000000000013');
  IF result.code<>'invalid_identifier_role' THEN RAISE EXCEPTION 'outbound mention gained command authority'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'appeal_reference','self_identifier','GST Tribunal','APL/2','appeal','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'APL/2','[]',NULL,'14700000-0000-0000-0000-000000000014');
  IF result.code<>'invalid_evidence' THEN RAISE EXCEPTION 'cross-Matter evidence was accepted'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'proceeding_case_id','self_identifier','GST Tribunal','GST/009/2026','suffix collision','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'Reference GST/009/20260','[]',NULL,'14700000-0000-0000-0000-000000000016');
  IF result.code<>'invalid_evidence' THEN RAISE EXCEPTION 'alphanumeric evidence suffix near-collision was accepted'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev,'proceeding_case_id','self_identifier','GST Tribunal','GST/010/2026','prefix collision','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'Reference XGST/010/2026','[]',NULL,'14700000-0000-0000-0000-000000000017');
  IF result.code<>'invalid_evidence' THEN RAISE EXCEPTION 'alphanumeric evidence prefix near-collision was accepted'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',rev-1,'appeal_reference','self_identifier','GST Tribunal','APL/3','appeal','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'APL/3','[]',NULL,'14700000-0000-0000-0000-000000000015');
  IF result.code<>'conflict' THEN RAISE EXCEPTION 'stale Matter revision was accepted'; END IF;
  IF (SELECT count(*) FROM public.matter_identifiers)<>identifier_count
     OR (SELECT count(*) FROM public.matter_identifier_decisions)<>decision_count
     OR (SELECT count(*) FROM public.activity_events WHERE event_type='matter.identifier_changed')<>activity_count
     OR (SELECT count(*) FROM public.matter_identifier_command_receipts)<>receipt_count THEN
    RAISE EXCEPTION 'failed commands left partial identifier/decision/Activity/receipt writes';
  END IF;
END $failure_matrix$;

-- Role, membership, ambiguity, and tenant failures all fail closed.
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000004',true);
DO $viewer_denial$ DECLARE result record; rev bigint; BEGIN
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000002',rev,'court_case_number','self_identifier','High Court','WP/1/2026','WP/1/2026','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'WP/1/2026','[]',NULL,'14700000-0000-0000-0000-000000000021');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Viewer was allowed'; END IF;
END $viewer_denial$;
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000005',true);
DO $suspended_denial$ DECLARE result record; rev bigint; BEGIN
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000002',rev,'court_case_number','self_identifier','High Court','WP/2/2026','WP/2/2026','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'WP/2/2026','[]',NULL,'14700000-0000-0000-0000-000000000022');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'suspended member was allowed'; END IF;
END $suspended_denial$;
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000007',true);
DO $ambiguous_denial$ DECLARE result record; rev bigint; BEGIN
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000002',rev,'court_case_number','self_identifier','High Court','WP/3/2026','WP/3/2026','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'WP/3/2026','[]',NULL,'14700000-0000-0000-0000-000000000023');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'ambiguous member was allowed'; END IF;
END $ambiguous_denial$;
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000003',true);
DO $foreign_denial$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000004',1,'court_case_number','self_identifier','High Court','WP/4/2026','WP/4/2026','e1470000-0000-0000-0000-000000000004','01470000-0000-0000-0000-000000000004',1,'WP/4/2026','[]',NULL,'14700000-0000-0000-0000-000000000024');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'foreign Matter did not fail closed'; END IF;
END $foreign_denial$;

-- Replay is stable; changed payload with the same key conflicts.
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000001',true);
DO $replay_and_correction$
DECLARE result record; old_id uuid:=current_setting('test.identifier.owner')::uuid; matter_revision bigint; new_id uuid;
BEGIN
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',1,'proceeding_case_id','self_identifier',' GST Tribunal ',' gst / 001 / 2026 ','GST/001/2026','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'Proceeding reference GST / 001 / 2026','[{"x":0.1,"y":0.1,"width":0.2,"height":0.1}]','Verified from source','14700000-0000-0000-0000-000000000001');
  IF result.code<>'ok' OR NOT result.replayed OR result.identifier_id<>old_id THEN RAISE EXCEPTION 'activation replay failed'; END IF;
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000001',1,'proceeding_case_id','self_identifier','GST Tribunal','GST/009/2026','changed','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'GST/009/2026','[]',NULL,'14700000-0000-0000-0000-000000000001');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'changed replay was accepted'; END IF;
  SELECT revision INTO matter_revision FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.correct_matter_identifier(old_id,1,matter_revision,'proceeding_case_id','self_identifier','GST Tribunal','GST/002/2026','GST/002/2026','e1470000-0000-0000-0000-000000000001','01470000-0000-0000-0000-000000000001',1,'Correct reference GST/002/2026','[]','Clerical correction','14700000-0000-0000-0000-000000000031');
  IF result.code<>'ok' OR result.previous_identifier_id<>old_id OR result.identifier_id IS NULL THEN RAISE EXCEPTION 'atomic correction failed: %',result.code; END IF;
  new_id:=result.identifier_id;
  IF NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=old_id AND lifecycle_state='revoked' AND revision=2 AND revocation_reason='Clerical correction')
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=new_id AND predecessor_identifier_id=old_id AND lifecycle_state='active')
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifier_decisions WHERE identifier_id=new_id AND previous_identifier_id=old_id AND action='correct') THEN
    RAISE EXCEPTION 'correction history/lineage failed';
  END IF;
  PERFORM set_config('test.identifier.corrected',new_id::text,true);
END $replay_and_correction$;

DO $revoke$
DECLARE result record; identifier uuid:=current_setting('test.identifier.corrected')::uuid; matter_revision bigint;
BEGIN
  SELECT revision INTO matter_revision FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000001';
  SELECT * INTO result FROM public.revoke_matter_identifier(identifier,1,matter_revision,'No longer authoritative','14700000-0000-0000-0000-000000000032');
  IF result.code<>'ok' OR result.identifier_revision<>2 THEN RAISE EXCEPTION 'revoke failed: %',result.code; END IF;
  SELECT * INTO result FROM public.revoke_matter_identifier(identifier,1,matter_revision,'No longer authoritative','14700000-0000-0000-0000-000000000032');
  IF result.code<>'ok' OR NOT result.replayed THEN RAISE EXCEPTION 'revoke replay failed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.matter_identifier_decisions WHERE identifier_id=identifier AND action='revoke' AND reason='No longer authoritative') THEN RAISE EXCEPTION 'revoke history failed'; END IF;
END $revoke$;

-- Activate a reservation used to prove ordinary Trash/Restore and permanent
-- purge behavior. The key is never released by either lifecycle transition.
DO $purge_identifier_activate$
DECLARE result record; rev bigint;
BEGIN
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000003';
  SELECT * INTO result FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000003',rev,'court_case_number','self_identifier','Bombay High Court','WP/777/2026','WP/777/2026','e1470000-0000-0000-0000-000000000003','01470000-0000-0000-0000-000000000003',1,'Case number WP/777/2026','[{"x":0.2,"y":0.2,"width":0.3,"height":0.1}]','Verified before purge','14700000-0000-0000-0000-000000000041');
  IF result.code<>'ok' THEN RAISE EXCEPTION 'purge identifier activation failed: %',result.code; END IF;
  PERFORM set_config('test.identifier.purge',result.identifier_id::text,true);
END $purge_identifier_activate$;

DO $trash_restore_preserves$
DECLARE trashed record; restored record; collision record; rev bigint; identifier uuid:=current_setting('test.identifier.purge')::uuid;
BEGIN
  SELECT * INTO trashed FROM public.trash_resource('matter','d1470000-0000-0000-0000-000000000003','identifier.fixture.trash.one');
  IF trashed.code<>'trashed' THEN RAISE EXCEPTION 'ordinary Matter Trash failed: %',trashed.code; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=identifier AND lifecycle_state='active' AND evidence_quote='Case number WP/777/2026' AND evidence_purged_at IS NULL) THEN RAISE EXCEPTION 'ordinary Trash scrubbed/released identifier evidence'; END IF;
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO collision FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000002',rev,'court_case_number','self_identifier','Bombay High Court','WP/777/2026','collision','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'WP/777/2026','[]',NULL,'14700000-0000-0000-0000-000000000042');
  IF collision.code<>'identifier_conflict' THEN RAISE EXCEPTION 'Trash released verified identifier reservation: %',collision.code; END IF;
  SELECT * INTO restored FROM public.restore_trash_operation(trashed.operation_id,'identifier.fixture.restore.one');
  IF restored.code<>'restored' THEN RAISE EXCEPTION 'ordinary Matter Restore failed: %',restored.code; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=identifier AND evidence_document_version_id='01470000-0000-0000-0000-000000000003' AND evidence_quote='Case number WP/777/2026' AND evidence_purged_at IS NULL) THEN RAISE EXCEPTION 'ordinary Restore changed identifier evidence'; END IF;
END $trash_restore_preserves$;

-- Viewer can read the narrow exact-Matter projection, but suggestions,
-- revoked rows, excerpts, regions, actors, and foreign Matters do not leak.
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000004',true);
DO $projection$
DECLARE result record; encoded text;
BEGIN
  SELECT * INTO result FROM public.read_matter_identifiers('d1470000-0000-0000-0000-000000000001');
  encoded:=result.identifiers::text;
  IF result.outcome<>'ok' OR jsonb_array_length(result.identifiers)<>1
     OR encoded ~* 'evidenceQuote|evidenceRegions|verifiedBy|SUG/1/2026|GST/002/2026'
     OR NOT (result.identifiers @> '[{"identifierKind":"notice_reference"}]'::jsonb) THEN
    RAISE EXCEPTION 'narrow projection inclusion/exclusion failed: %',encoded;
  END IF;
  SELECT * INTO result FROM public.read_matter_identifiers('d1470000-0000-0000-0000-000000000004');
  IF result.outcome<>'unavailable' OR result.identifiers<>'[]'::jsonb THEN RAISE EXCEPTION 'foreign projection disclosed'; END IF;
END $projection$;
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000005',true);
DO $suspended_projection$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.read_matter_identifiers('d1470000-0000-0000-0000-000000000001');
  IF result.outcome<>'unavailable' THEN RAISE EXCEPTION 'suspended projection disclosed'; END IF;
END $suspended_projection$;

-- Permanent purge uses the existing root-operation workflow. Preparing the
-- database deletes the source version, which atomically scrubs evidence while
-- retaining the opaque normalized reservation and append-only decisions.
SELECT set_config('request.jwt.claim.sub','a1470000-0000-0000-0000-000000000001',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','a1470000-0000-0000-0000-000000000001','iat',extract(epoch FROM now())::bigint)::text,true);
DO $permanent_purge$
DECLARE trashed record; impact record; queued record; job record; prepared record; deletion record; completed record;
  identifier uuid:=current_setting('test.identifier.purge')::uuid; before_revision bigint; collision record; rev bigint;
BEGIN
  SELECT revision INTO before_revision FROM public.matter_identifiers WHERE id=identifier;
  SELECT * INTO trashed FROM public.trash_resource('matter','d1470000-0000-0000-0000-000000000003','identifier.fixture.trash.purge');
  IF trashed.code<>'trashed' THEN RAISE EXCEPTION 'purge setup Trash failed: %',trashed.code; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(trashed.operation_id);
  IF NOT impact.can_purge THEN RAISE EXCEPTION 'identifier incorrectly blocked permanent purge'; END IF;
  SELECT * INTO queued FROM public.confirm_trash_purge(trashed.operation_id,impact.impact_fingerprint,'PURGE-147','identifier.fixture.confirm.purge');
  IF queued.code<>'queued' THEN RAISE EXCEPTION 'identifier Matter purge did not queue: %',queued.code; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=trashed.operation_id;
  SELECT * INTO prepared FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF prepared.code<>'prepared' THEN RAISE EXCEPTION 'identifier Matter purge preparation failed: %',prepared.code; END IF;
  IF EXISTS(SELECT 1 FROM public.document_versions WHERE id='01470000-0000-0000-0000-000000000003')
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifiers WHERE id=identifier
       AND lifecycle_state='active' AND evidence_document_id IS NULL AND evidence_document_version_id IS NULL
       AND evidence_page_number IS NULL AND evidence_quote IS NULL AND evidence_regions='[]'::jsonb
       AND evidence_purged_at IS NOT NULL AND raw_value='WP/777/2026' AND display_value='WP/777/2026'
       AND issuer_namespace_raw='BOMBAY HIGH COURT' AND revision=before_revision+1)
     OR NOT EXISTS(SELECT 1 FROM public.matter_identifier_decisions WHERE identifier_id=identifier AND action='activate') THEN
    RAISE EXCEPTION 'purge did not scrub evidence and retain opaque reservation/history';
  END IF;
  SELECT * INTO deletion FROM public.claim_trash_purge_storage_deletions(job.job_id,job.lease_token,25,120);
  IF deletion.deletion_id IS NOT NULL THEN
    SELECT * INTO completed FROM public.finish_trash_purge_storage_deletion(deletion.deletion_id,deletion.lease_token,'deleted');
    IF completed.code<>'deleted' THEN RAISE EXCEPTION 'purge storage reconciliation failed'; END IF;
  END IF;
  SELECT * INTO completed FROM public.finish_trash_purge_attempt(job.job_id,job.lease_token);
  IF completed.code<>'purged' OR (SELECT record_state::text FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000003')<>'purged' THEN
    RAISE EXCEPTION 'identifier Matter purge did not finish';
  END IF;
  SELECT revision INTO rev FROM public.matters WHERE id='d1470000-0000-0000-0000-000000000002';
  SELECT * INTO collision FROM public.activate_matter_identifier('d1470000-0000-0000-0000-000000000002',rev,'court_case_number','self_identifier','Bombay High Court','WP/777/2026','stale rebind','e1470000-0000-0000-0000-000000000002','01470000-0000-0000-0000-000000000002',1,'WP/777/2026','[]',NULL,'14700000-0000-0000-0000-000000000043');
  IF collision.code<>'identifier_conflict' THEN RAISE EXCEPTION 'purged reservation was rebound: %',collision.code; END IF;
END $permanent_purge$;

DO $append_only_and_inventory$
DECLARE denied boolean:=false;
BEGIN
  BEGIN UPDATE public.matter_identifier_decisions SET reason='changed' WHERE action='activate'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'append-only identifier history was mutable'; END IF;
  IF (SELECT count(*) FROM public.matter_identifier_decisions)<>6
     OR (SELECT count(*) FROM public.activity_events WHERE event_type='matter.identifier_changed')<>6
     OR (SELECT count(*) FROM public.activity_projector_outbox_events outbox JOIN public.activity_events event ON event.id=outbox.activity_event_id WHERE event.event_type='matter.identifier_changed')<>6
     OR EXISTS(SELECT 1 FROM public.outbox_events WHERE event_kind LIKE 'matter.identifier%') THEN
    RAISE EXCEPTION 'successful state-change effect inventory was inconsistent';
  END IF;
END $append_only_and_inventory$;

SET LOCAL ROLE authenticated;
DO $authenticated_direct_dml_denial$ DECLARE denied boolean:=false; BEGIN
  BEGIN INSERT INTO public.matter_identifier_command_receipts(org_id,actor_user_id,idempotency_key,command,request_fingerprint,identifier_id,result_identifier_revision,result_matter_revision)
    VALUES('b1470000-0000-0000-0000-000000000001','a1470000-0000-0000-0000-000000000001',gen_random_uuid(),'revoke',repeat('a',64),current_setting('test.identifier.purge')::uuid,1,1);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct identifier receipt DML succeeded'; END IF;
END $authenticated_direct_dml_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_direct_dml_denial$ DECLARE denied boolean:=false; BEGIN
  BEGIN UPDATE public.matter_identifiers SET display_value='forged'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role forged identifier state'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.matter_identifier_decisions; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role deleted identifier history'; END IF;
END $service_direct_dml_denial$;
RESET ROLE;

ROLLBACK;
