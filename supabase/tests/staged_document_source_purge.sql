-- Fail-closed staged-source purge authority.  This fixture is rollback-only:
-- it proves the service contract without making any Storage call.
BEGIN;

DO $setup$
DECLARE
  org_a uuid := '59000000-0000-0000-0000-000000000001';
  org_b uuid := '59000000-0000-0000-0000-000000000002';
  user_a uuid := '59100000-0000-0000-0000-000000000001';
  user_b uuid := '59100000-0000-0000-0000-000000000002';
  client_a uuid := '59200000-0000-0000-0000-000000000001';
  matter_a uuid := '59300000-0000-0000-0000-000000000001';
  source_a uuid := '59400000-0000-0000-0000-000000000001';
  source_blocked uuid := '59400000-0000-0000-0000-000000000002';
  source_recovery uuid := '59400000-0000-0000-0000-000000000003';
  source_unlinked uuid := '59400000-0000-0000-0000-000000000004';
  source_cap uuid := '59400000-0000-0000-0000-000000000005';
  asset_a uuid := '59500000-0000-0000-0000-000000000001';
  asset_blocked uuid := '59500000-0000-0000-0000-000000000002';
  asset_recovery uuid := '59500000-0000-0000-0000-000000000003';
  asset_unlinked uuid := '59500000-0000-0000-0000-000000000004';
  asset_cap uuid := '59500000-0000-0000-0000-000000000005';
  intake_a uuid := '59600000-0000-0000-0000-000000000001';
  intake_blocked uuid := '59600000-0000-0000-0000-000000000002';
  intake_recovery uuid := '59600000-0000-0000-0000-000000000003';
  intake_unlinked uuid := '59600000-0000-0000-0000-000000000004';
  intake_cap uuid := '59600000-0000-0000-0000-000000000005';
  document_a uuid := '59700000-0000-0000-0000-000000000001';
  document_blocked uuid := '59700000-0000-0000-0000-000000000002';
  document_recovery uuid := '59700000-0000-0000-0000-000000000003';
  document_cap uuid := '59700000-0000-0000-0000-000000000005';
  version_a uuid := '59800000-0000-0000-0000-000000000001';
  version_blocked uuid := '59800000-0000-0000-0000-000000000002';
  version_recovery uuid := '59800000-0000-0000-0000-000000000003';
  version_cap uuid := '59800000-0000-0000-0000-000000000005';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',user_a,'authenticated','authenticated','source-purge-a@example.test','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',user_b,'authenticated','authenticated','source-purge-b@example.test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES (org_a,'Source purge A',user_a),(org_b,'Source purge B',user_b);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_a,org_a,'Source purge client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_a,org_a,client_a,'Source purge matter');

  INSERT INTO public.staged_documents(id,org_id,uploaded_by,storage_path,status,intake_matter_id) VALUES
    (source_a,org_a,user_a,'staging/'||org_a||'/59900000-0000-0000-0000-000000000001/original.pdf','ready_to_assign',matter_a),
    (source_blocked,org_a,user_a,'staging/'||org_a||'/59900000-0000-0000-0000-000000000002/original.pdf','ready_to_assign',matter_a),
    (source_recovery,org_a,user_a,'staging/'||org_a||'/59900000-0000-0000-0000-000000000003/original.pdf','ready_to_assign',matter_a),
    (source_unlinked,org_a,user_a,'staging/'||org_a||'/59900000-0000-0000-0000-000000000004/original.pdf','ready_to_assign',matter_a),
    (source_cap,org_a,user_a,'staging/'||org_a||'/59900000-0000-0000-0000-000000000005/original.pdf','ready_to_assign',matter_a);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
    (asset_a,org_a,'documents','orgs/'||org_a||'/assets/'||asset_a||'/original.pdf',repeat('a',64),17,'application/pdf','available',now(),1,user_a),
    (asset_blocked,org_a,'documents','orgs/'||org_a||'/assets/'||asset_blocked||'/original.pdf',repeat('b',64),19,'application/pdf','available',now(),1,user_a),
    (asset_recovery,org_a,'documents','orgs/'||org_a||'/assets/'||asset_recovery||'/original.pdf',repeat('c',64),23,'application/pdf','available',now(),1,user_a),
    (asset_unlinked,org_a,'documents','orgs/'||org_a||'/assets/'||asset_unlinked||'/original.pdf',repeat('d',64),29,'application/pdf','available',now(),1,user_a),
    (asset_cap,org_a,'documents','orgs/'||org_a||'/assets/'||asset_cap||'/original.pdf',repeat('e',64),31,'application/pdf','available',now(),1,user_a);
  INSERT INTO public.intake_items(id,org_id,asset_id,intended_matter_id,state,uploaded_by,assigned_at) VALUES
    (intake_a,org_a,asset_a,matter_a,'assigned',user_a,now()),
    (intake_blocked,org_a,asset_blocked,matter_a,'assigned',user_a,now()),
    (intake_recovery,org_a,asset_recovery,matter_a,'assigned',user_a,now()),
    (intake_unlinked,org_a,asset_unlinked,matter_a,'assigned',user_a,now()),
    (intake_cap,org_a,asset_cap,matter_a,'assigned',user_a,now());
  INSERT INTO public.documents(id,org_id,matter_id,display_title,status,storage_path,created_by) VALUES
    (document_a,org_a,matter_a,'Purge A','placed',NULL,user_a),
    (document_blocked,org_a,matter_a,'Purge running','placed',NULL,user_a),
    (document_recovery,org_a,matter_a,'Purge recovery','placed',NULL,user_a),
    (document_cap,org_a,matter_a,'Purge cap','placed',NULL,user_a);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,created_by,validated_at,promoted_at) VALUES
    (version_a,org_a,document_a,asset_a,1,'original.pdf',1,'valid','current',user_a,now(),now()),
    (version_blocked,org_a,document_blocked,asset_blocked,1,'original.pdf',1,'valid','current',user_a,now(),now()),
    (version_recovery,org_a,document_recovery,asset_recovery,1,'original.pdf',1,'valid','current',user_a,now(),now()),
    (version_cap,org_a,document_cap,asset_cap,1,'original.pdf',1,'valid','current',user_a,now(),now());
  UPDATE public.documents SET current_version_id=CASE id
    WHEN document_a THEN version_a WHEN document_blocked THEN version_blocked WHEN document_recovery THEN version_recovery WHEN document_cap THEN version_cap END
    WHERE id IN (document_a,document_blocked,document_recovery,document_cap);
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES
    (org_a,intake_a,document_a,version_a,user_a),
    (org_a,intake_blocked,document_blocked,version_blocked,user_a),
    (org_a,intake_recovery,document_recovery,version_recovery,user_a),
    (org_a,intake_cap,document_cap,version_cap,user_a);
  -- A running analysis with no lease is unknown active work and must block.
  INSERT INTO public.source_analysis_runs(org_id,asset_id,state,request_key,started_at)
    VALUES(org_a,asset_blocked,'running','purge-null-lease-work',now());
  INSERT INTO public.staged_document_backfill_items(
    org_id,legacy_staged_document_id,safe_item_key,outcome,canonical_asset_id,canonical_intake_item_id,
    observed_sha256,observed_byte_size,safe_reason_code,terminal_classified_at,transfer_completed_at
  ) VALUES
    (org_a,source_a,'legacy-staged/'||source_a::text,'transfer_pending',asset_a,intake_a,repeat('a',64),17,'canonical_transfer_completed',now(),now()),
    (org_a,source_blocked,'legacy-staged/'||source_blocked::text,'transfer_pending',asset_blocked,intake_blocked,repeat('b',64),19,'canonical_transfer_completed',now(),now()),
    (org_a,source_recovery,'legacy-staged/'||source_recovery::text,'transfer_pending',asset_recovery,intake_recovery,repeat('c',64),23,'canonical_transfer_completed',now(),now()),
    (org_a,source_unlinked,'legacy-staged/'||source_unlinked::text,'transfer_pending',asset_unlinked,intake_unlinked,repeat('d',64),29,'canonical_transfer_completed',now(),now()),
    (org_a,source_cap,'legacy-staged/'||source_cap::text,'transfer_pending',asset_cap,intake_cap,repeat('e',64),31,'canonical_transfer_completed',now(),now()-interval '1 day');
  INSERT INTO public.staged_document_retirement_audit_items(org_id,legacy_staged_document_id,outcome,audited_at) VALUES
    (org_a,source_a,'verified_equal',now()),
    (org_a,source_blocked,'verified_equal',now()),
    (org_a,source_recovery,'verified_equal',now()),
    (org_a,source_unlinked,'verified_equal',now()),
    (org_a,source_cap,'verified_equal',now());
END $setup$;

-- Unassigned Intake remains human-controlled.  Even with a verified transfer,
-- a staging source is not redundant until an immutable current document
-- version proves assignment to the matter.
DO $unassigned_never_auto_purges$
BEGIN
  IF public.staged_document_source_purge_is_eligible(
    '59000000-0000-0000-0000-000000000001',
    '59400000-0000-0000-0000-000000000004'
  ) THEN
    RAISE EXCEPTION 'unassigned Intake became an automatic purge candidate';
  END IF;
END $unassigned_never_auto_purges$;

-- An exhausted candidate is fenced without overflowing the bounded counter;
-- later candidates remain available to the same maintenance authority.
INSERT INTO public.staged_document_source_purge_tombstones(
  org_id,legacy_staged_document_id,state,lease_token,lease_expires_at,attempt_count
) VALUES (
  '59000000-0000-0000-0000-000000000001',
  '59400000-0000-0000-0000-000000000005',
  'claimed','59900000-0000-0000-0000-000000000005',now()-interval '1 minute',1000
);
SET LOCAL ROLE service_role;
DO $attempt_cap$
DECLARE org_a uuid := '59000000-0000-0000-0000-000000000001'; report public.staged_document_source_purge_reports%ROWTYPE;
BEGIN
  IF EXISTS (SELECT 1 FROM public.claim_staged_document_source_purge_batch(org_a,1)) THEN
    RAISE EXCEPTION 'attempt-cap candidate was re-leased';
  END IF;
  SELECT * INTO report FROM public.staged_document_source_purge_reports WHERE org_id=org_a;
  IF report.recovery_required_count <> 1 THEN RAISE EXCEPTION 'attempt cap did not become durable recovery'; END IF;
END $attempt_cap$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service$
DECLARE
  org_a uuid := '59000000-0000-0000-0000-000000000001';
  org_b uuid := '59000000-0000-0000-0000-000000000002';
  source_a uuid := '59400000-0000-0000-0000-000000000001';
  source_blocked uuid := '59400000-0000-0000-0000-000000000002';
  source_recovery uuid := '59400000-0000-0000-0000-000000000003';
  source_unlinked uuid := '59400000-0000-0000-0000-000000000004';
  claim record; grant_row record; result record;
  source_digest_before text; source_digest_after text; direct_dml_denied boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.staged_document_source_purge_tombstones(org_id,legacy_staged_document_id)
      VALUES(org_a,source_a);
  EXCEPTION WHEN insufficient_privilege THEN direct_dml_denied := true;
  END;
  IF NOT direct_dml_denied THEN RAISE EXCEPTION 'service direct purge-tombstone DML allowed'; END IF;
  SELECT md5(string_agg(id::text || ':' || status::text || ':' || storage_path, ',' ORDER BY id))
    INTO source_digest_before FROM public.staged_documents WHERE org_id=org_a;
  SELECT * INTO claim FROM public.claim_staged_document_source_purge_batch(org_a, 1)
    WHERE legacy_staged_document_id=source_a;
  IF NOT FOUND OR claim.code <> 'purge_required' OR claim.purge_lease_token IS NULL THEN
    RAISE EXCEPTION 'fresh equal audited source was not claimed for purge';
  END IF;
  SELECT * INTO grant_row FROM public.get_staged_document_source_purge_grant(org_a,source_a,claim.purge_lease_token);
  IF NOT FOUND OR grant_row.code <> 'ok' OR grant_row.source_bucket_id <> 'staging'
    OR grant_row.destination_bucket_id <> 'documents' OR grant_row.expected_byte_size <> 17
    OR grant_row.expected_sha256 <> repeat('a',64) THEN
    RAISE EXCEPTION 'live purge grant did not bind fresh source/canonical proof';
  END IF;
  SELECT * INTO grant_row FROM public.get_staged_document_source_purge_grant(org_b,source_a,claim.purge_lease_token);
  IF NOT FOUND OR grant_row.code <> 'not_found'
    OR grant_row.source_bucket_id IS NOT NULL OR grant_row.source_object_key IS NOT NULL
    OR grant_row.destination_bucket_id IS NOT NULL OR grant_row.destination_object_key IS NOT NULL
    OR grant_row.expected_byte_size IS NOT NULL OR grant_row.expected_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'cross-tenant purge grant exposed sensitive evidence';
  END IF;
  SELECT * INTO result FROM public.record_staged_document_source_purge_intent(
    org_a,source_a,claim.purge_lease_token,17,repeat('a',64),1,17,repeat('a',64),1
  );
  IF result.code <> 'delete_intended' THEN RAISE EXCEPTION 'fresh equality did not create durable intent'; END IF;
  SELECT * INTO result FROM public.confirm_staged_document_source_purge(
    org_a,source_a,claim.purge_lease_token,'storage_deleted'
  );
  IF result.code <> 'deleted' THEN RAISE EXCEPTION 'Storage confirmation did not create tombstone'; END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='staged_document_source_purge_tombstones'
      AND column_name IN ('storage_path','object_key','filename','sha256','byte_size','content','error')
  ) THEN RAISE EXCEPTION 'purge tombstone retained source content or locator fields'; END IF;
  SELECT * INTO claim FROM public.claim_staged_document_source_purge_batch(org_a,1)
    WHERE legacy_staged_document_id=source_recovery;
  IF NOT FOUND THEN RAISE EXCEPTION 'recovery fixture source was not claimed'; END IF;
  SELECT * INTO result FROM public.record_staged_document_source_purge_intent(
    org_a,source_recovery,claim.purge_lease_token,23,repeat('c',64),1,23,repeat('c',64),1
  );
  IF result.code <> 'delete_intended' THEN RAISE EXCEPTION 'late-blocker fixture did not create durable intent'; END IF;
  PERFORM set_config('test.purge_recovery_token',claim.purge_lease_token::text,true);
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='staged_document_source_purge_reports'
      AND column_name IN ('storage_path','object_key','legacy_staged_document_id','sha256','byte_size','content','error')
  ) THEN RAISE EXCEPTION 'purge report exposed sensitive evidence fields'; END IF;
  SELECT md5(string_agg(id::text || ':' || status::text || ':' || storage_path, ',' ORDER BY id))
    INTO source_digest_after FROM public.staged_documents WHERE org_id=org_a;
  IF source_digest_after IS DISTINCT FROM source_digest_before THEN
    RAISE EXCEPTION 'purge authority changed a legacy staged source row';
  END IF;
END $service$;
RESET ROLE;

-- Matter-level backup/hold/export/retention policy governs the canonical
-- document, not its verified redundant staging source.

SET LOCAL ROLE service_role;
DO $canonical_policy_does_not_block_staging_cleanup$
DECLARE
  org_a uuid := '59000000-0000-0000-0000-000000000001';
  source_recovery uuid := '59400000-0000-0000-0000-000000000003';
  token uuid := current_setting('test.purge_recovery_token')::uuid; result record; report public.staged_document_source_purge_reports%ROWTYPE;
BEGIN
  SELECT * INTO result FROM public.create_staged_document_source_purge_blocker(
    org_a,'canonical_asset',NULL,'59500000-0000-0000-0000-000000000003','backup'
  );
  IF result.code <> 'not_applicable' THEN
    RAISE EXCEPTION 'canonical backup policy was incorrectly accepted as a staging blocker';
  END IF;
  SELECT * INTO result FROM public.confirm_staged_document_source_purge(
    org_a,source_recovery,token,'storage_deleted'
  );
  IF result.code <> 'deleted' THEN RAISE EXCEPTION 'rejected late writer prevented safe confirmation'; END IF;
  IF EXISTS (SELECT 1 FROM public.claim_staged_document_source_purge_batch(org_a,1)) THEN
    RAISE EXCEPTION 'blocked, deleted, or recovery-fenced source was re-claimed';
  END IF;
  SELECT * INTO report FROM public.staged_document_source_purge_reports WHERE org_id=org_a;
  IF report.deleted_tombstone_count <> 2 OR report.recovery_required_count <> 1
    OR report.active_blocker_count <> 0 OR report.active_purge_lease_count <> 0 THEN
    RAISE EXCEPTION 'content-free purge report counts were inconsistent';
  END IF;
END $canonical_policy_does_not_block_staging_cleanup$;
RESET ROLE;

-- Scope FKs prevent an asset/source blocker from moving between organisations;
-- even privileged direct repair updates are therefore unable to change its
-- authority scope behind the service command.
SET LOCAL ROLE service_role;
DO $blocker_scope$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.create_staged_document_source_purge_blocker(
    '59000000-0000-0000-0000-000000000001','legacy_source',
    '59400000-0000-0000-0000-000000000004',NULL,'recovery'
  );
  IF result.code <> 'created' THEN RAISE EXCEPTION 'staging recovery blocker was not created'; END IF;
END $blocker_scope$;
RESET ROLE;
DO $blocker_org_move$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    UPDATE public.staged_document_source_purge_blockers
    SET org_id='59000000-0000-0000-0000-000000000002'
    WHERE org_id='59000000-0000-0000-0000-000000000001'
      AND legacy_staged_document_id='59400000-0000-0000-0000-000000000004';
  EXCEPTION WHEN foreign_key_violation THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'blocker organisation move bypassed scope authority'; END IF;
END $blocker_org_move$;

SET LOCAL ROLE authenticated;
DO $browser$
DECLARE denied boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.claim_staged_document_source_purge_batch('59000000-0000-0000-0000-000000000001',1);
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could claim staged-source purge'; END IF;
  denied := false;
  BEGIN
    PERFORM 1 FROM public.staged_document_source_purge_tombstones;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could read content-free purge tombstones'; END IF;
  denied := false;
  BEGIN
    PERFORM 1 FROM public.staged_document_source_purge_reports;
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'browser could read service-only purge reports'; END IF;
END $browser$;
RESET ROLE;

ROLLBACK;
