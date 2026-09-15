import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

requireNode24()
const project = 'dms-release-journey-162'
const workdir = process.env.RELEASE_JOURNEY_SUPABASE_WORKDIR
if (!workdir || !readFileSync(join(workdir, 'supabase/config.toml'), 'utf8').includes(`project_id = "${project}"`)) {
  throw new Error(`Release-journey database operations require the owned ${project} workdir.`)
}
const container = `supabase_db_${project}`
const operation = process.argv[2]
const ownerEmail = process.env.RELEASE_JOURNEY_OWNER_EMAIL
if (!ownerEmail || !/^release-owner-[0-9a-f]{12}@acceptance\.test$/.test(ownerEmail)) {
  throw new Error('Release-journey database operations require the per-run Owner address.')
}

function sql(source, { tuples = false } = {}) {
  const args = ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres']
  if (tuples) args.splice(4, 0, '-qAt')
  const result = spawnSync('docker', args, { input: source, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 })
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? `${result.stderr}\n${result.stdout}`)
  return result.stdout.trim()
}

const prepare = String.raw`
DO $journey$
DECLARE
  v_owner_id uuid; v_org_id uuid; v_primary_matter uuid; v_alternate_matter uuid;
  intended_intake uuid; global_intake uuid; intended_event uuid;
  intended_document uuid; intended_version uuid; intended_asset uuid;
  processing_id uuid:=gen_random_uuid(); source_run_id uuid:=gen_random_uuid();
  processing_lease uuid:=gen_random_uuid(); source_lease uuid:=gen_random_uuid();
  validation record; assigned record; finished record; produced record;
BEGIN
  SELECT users.id, organisations.id INTO STRICT v_owner_id, v_org_id
  FROM auth.users users JOIN public.organisations organisations ON organisations.created_by=users.id
  WHERE users.email='${ownerEmail}' AND organisations.name='Release Journey Organisation';
  SELECT matter.id INTO STRICT v_primary_matter FROM public.matters matter WHERE matter.org_id=v_org_id AND matter.title='Release Journey Primary';
  SELECT matter.id INTO STRICT v_alternate_matter FROM public.matters matter WHERE matter.org_id=v_org_id AND matter.title='Release Journey Alternate';
  SELECT intake.id INTO STRICT intended_intake FROM public.intake_items intake
    JOIN public.upload_sessions session ON session.id=intake.upload_session_id AND session.org_id=intake.org_id
    WHERE intake.org_id=v_org_id AND session.declared_filename='release-matter-origin.pdf';
  SELECT intake.id INTO STRICT global_intake FROM public.intake_items intake
    JOIN public.upload_sessions session ON session.id=intake.upload_session_id AND session.org_id=intake.org_id
    WHERE intake.org_id=v_org_id AND session.declared_filename='release-global-intake.pdf';

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  SELECT * INTO validation FROM public.validate_document_intake_asset(intended_intake,4,'ready',gen_random_uuid());
  IF validation.code<>'ok' THEN RAISE EXCEPTION 'Matter-origin validation failed: %',validation.code; END IF;
  SELECT * INTO validation FROM public.validate_document_intake_asset(global_intake,4,'ready',gen_random_uuid());
  IF validation.code<>'ok' THEN RAISE EXCEPTION 'Global validation failed: %',validation.code; END IF;
  SELECT id INTO STRICT intended_event FROM public.outbox_events
    WHERE aggregate_id=intended_intake AND event_kind='document.intake_validated.v1';
  SELECT * INTO assigned FROM public.auto_assign_intended_matter_intake(intended_intake,intended_event);
  IF assigned.code<>'ok' OR assigned.document_id IS NULL OR assigned.document_version_id IS NULL THEN
    RAISE EXCEPTION 'Matter-origin materialisation failed: %',assigned.code;
  END IF;
  intended_document:=assigned.document_id; intended_version:=assigned.document_version_id;
  SELECT asset_id INTO STRICT intended_asset FROM public.document_versions WHERE id=intended_version;

  -- Worker-only precondition: represent a terminal provider failure without making
  -- a provider call or claiming D12 acquisition/extraction quality.
  INSERT INTO public.document_processing_runs(
    id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,
    started_at,lease_token,lease_expires_at,heartbeat_at
  ) VALUES (
    processing_id,v_org_id,intended_document,intended_version,'full',
    'release.manual-recovery.'||processing_id,'running','extracting',now(),
    processing_lease,now()+interval '10 minutes',now()
  );
  INSERT INTO public.source_analysis_runs(
    id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,
    provider,model_identifier,model_config_version,prompt_version,schema_version,
    catalogue_version,normalizer_version,started_at,attempt_count,lease_token,
    lease_expires_at,heartbeat_at
  ) VALUES (
    source_run_id,v_org_id,intended_asset,'ai_extraction.'||processing_id,
    'ai_extraction.'||processing_id,'ai_extraction','running','running',
    'local-acceptance-no-call','disabled-manual-recovery','release-fixture','v4.0',
    'document-extraction-v4','gst-legal-material-observation-catalogue-v3',
    'typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now()
  );
  INSERT INTO public.source_analysis_attempts(
    org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,
    model_identifier,model_config_version,prompt_version,schema_version,
    catalogue_version,normalizer_version,started_at
  ) VALUES (
    v_org_id,source_run_id,1,'running','initial','local-acceptance-no-call',
    'disabled-manual-recovery','release-fixture','v4.0','document-extraction-v4',
    'gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now()
  );
  INSERT INTO public.document_page_text_artifacts(
    org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,
    state,page_count,content_fingerprint
  ) VALUES (v_org_id,intended_document,intended_version,processing_id,source_run_id,'ready',4,repeat('a',64));
  INSERT INTO public.document_page_text_pages(
    org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,
    acquisition_method,quality_policy_version,quality_reasons,detected_languages
  ) SELECT v_org_id,artifact.id,page,'Synthetic local source page '||page,'[]','[]',
      md5(page::text)||md5(page::text),'native_pdf','native-pdf-quality-v1','{}','{}'
    FROM public.document_page_text_artifacts artifact CROSS JOIN generate_series(1,4) page
    WHERE artifact.source_analysis_run_id=source_run_id;
  SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(
    processing_id,processing_lease,source_run_id,source_lease,'provider_failed',0,0,1,'[]',false,
    jsonb_build_object('doc_type',NULL,'reference_number',NULL,'doc_date',NULL,
      'direction',NULL,'issued_by',NULL,'financial_years','[]'::jsonb,
      'summary',NULL,'prompt_version','v4.0')
  );
  IF finished.code<>'provider_failed' THEN RAISE EXCEPTION 'Manual recovery producer failed: %',finished.code; END IF;
  UPDATE public.document_processing_runs SET state='completed',stage='ready',completed_at=now(),
    lease_token=NULL,lease_expires_at=NULL WHERE id=processing_id;

  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(
    global_intake,'trusted-release-journey-v1',jsonb_build_array(
      jsonb_build_object('matter_id',v_primary_matter,'evidence',jsonb_build_array(
        jsonb_build_object('kind','verified_client_identifier','source_page_number',1))),
      jsonb_build_object('matter_id',v_alternate_matter,'evidence',jsonb_build_array(
        jsonb_build_object('kind','tax_period_overlap','source_page_number',2)))
    )
  );
  IF produced.code<>'ok' OR produced.review_item_id IS NULL THEN
    RAISE EXCEPTION 'Ambiguous placement producer failed: %',produced.code;
  END IF;
END $journey$;
SELECT jsonb_build_object(
  'primaryMatterId',(SELECT id FROM public.matters WHERE title='Release Journey Primary'),
  'alternateMatterId',(SELECT id FROM public.matters WHERE title='Release Journey Alternate'),
  'processingReviewId',(SELECT review.id FROM public.review_items review JOIN public.documents document ON document.id=review.document_id WHERE document.display_title='release-matter-origin' AND review.type='processing_recovery'),
  'placementReviewId',(SELECT review.id FROM public.review_items review JOIN public.intake_items intake ON intake.id=review.intake_id JOIN public.upload_sessions session ON session.id=intake.upload_session_id WHERE session.declared_filename='release-global-intake.pdf' AND review.type='ambiguous_placement')
);
`

const activate = String.raw`
DO $journey$
DECLARE v_owner_id uuid; v_org_id uuid; v_matter_id uuid; v_source_id uuid; v_target_id uuid;
  source_revision bigint; target_revision bigint; catalogue integer; result record;
BEGIN
  SELECT users.id, organisations.id INTO STRICT v_owner_id,v_org_id
    FROM auth.users users JOIN public.organisations organisations ON organisations.created_by=users.id
    WHERE users.email='${ownerEmail}' AND organisations.name='Release Journey Organisation';
  SELECT matter.id INTO STRICT v_matter_id FROM public.matters matter WHERE matter.org_id=v_org_id AND matter.title='Release Journey Primary';
  SELECT document.id INTO STRICT v_source_id
    FROM public.documents document JOIN public.document_versions version ON version.id=document.current_version_id
    JOIN public.upload_sessions session ON session.asset_id=version.asset_id
    WHERE document.matter_id=v_matter_id AND session.declared_filename='release-global-intake.pdf';
  SELECT document.id INTO STRICT v_target_id
    FROM public.documents document JOIN public.document_versions version ON version.id=document.current_version_id
    JOIN public.upload_sessions session ON session.asset_id=version.asset_id
    WHERE document.matter_id=v_matter_id AND session.declared_filename='release-matter-origin.pdf';
  -- Preconditions only: first-release placement/manual recovery do not expose a
  -- user-facing classification or relationship-authoring command. Keep the
  -- observed graph truthful by classifying these synthetic endpoints, then use
  -- the canonical governed relationship command for the actual edge.
  UPDATE public.documents SET document_class='proceeding'
    WHERE id IN (v_source_id,v_target_id) AND document_class IS NULL;
  SELECT lifecycle_revision INTO STRICT source_revision FROM public.documents WHERE id=v_source_id;
  SELECT lifecycle_revision INTO STRICT target_revision FROM public.documents WHERE id=v_target_id;
  SELECT max(catalogue_version) INTO STRICT catalogue FROM public.document_relationship_catalogue
    WHERE relationship_type='responds_to';
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',v_owner_id::text,true);
  SELECT * INTO result FROM public.activate_matter_timeline_relationship(
    v_matter_id,v_source_id,v_target_id,'responds_to',source_revision,target_revision,catalogue,
    'Synthetic release rehearsal relationship',gen_random_uuid()
  );
  IF result.code<>'ok' OR result.relationship_id IS NULL THEN
    RAISE EXCEPTION 'Governed relationship activation failed: %',result.code;
  END IF;
END $journey$;
`

const verify = String.raw`
DO $journey$
DECLARE v_owner_id uuid; v_org_id uuid; v_client_id uuid; v_primary_matter uuid; v_global_item uuid; v_recovery_item uuid;
BEGIN
  SELECT users.id,organisations.id INTO STRICT v_owner_id,v_org_id
    FROM auth.users users JOIN public.organisations organisations ON organisations.created_by=users.id
    WHERE users.email='${ownerEmail}' AND users.email_confirmed_at IS NOT NULL
      AND organisations.name='Release Journey Organisation';
  IF (SELECT count(*) FROM public.organisation_memberships membership JOIN public.organisations organisation ON organisation.owner_membership_id=membership.id
      WHERE membership.user_id=v_owner_id AND membership.org_id=v_org_id AND membership.state='active' AND membership.role='admin')<>1 THEN
    RAISE EXCEPTION 'Verified Owner tenant/role identity is not exact';
  END IF;
  SELECT client.id INTO STRICT v_client_id FROM public.clients client WHERE client.org_id=v_org_id AND client.name='Release Journey Client' AND client.record_state='active';
  SELECT matter.id INTO STRICT v_primary_matter FROM public.matters matter WHERE matter.org_id=v_org_id AND matter.client_id=v_client_id AND matter.title='Release Journey Primary' AND matter.record_state='active' AND matter.work_state='active';
  IF (SELECT count(*) FROM public.matters matter WHERE matter.org_id=v_org_id AND matter.client_id=v_client_id AND matter.title IN ('Release Journey Primary','Release Journey Alternate') AND matter.record_state='active')<>2 THEN
    RAISE EXCEPTION 'Client/Matter lifecycle lineage is incomplete';
  END IF;
  IF EXISTS(SELECT 1 FROM storage.buckets WHERE id='documents' AND public) THEN RAISE EXCEPTION 'Source bucket is public'; END IF;
  IF (SELECT count(*) FROM public.upload_sessions session JOIN public.file_assets asset ON asset.id=session.asset_id AND asset.org_id=session.org_id
      JOIN storage.objects object ON object.bucket_id=asset.bucket_id AND object.name=asset.object_key
      WHERE session.org_id=v_org_id AND session.declared_filename IN ('release-global-intake.pdf','release-matter-origin.pdf')
        AND session.state='finalized' AND asset.availability='available' AND asset.validated_page_count=4
        AND asset.sha256~'^[0-9a-f]{64}$')<>2 THEN RAISE EXCEPTION 'Private Storage/upload validation chain is incomplete'; END IF;
  IF (SELECT count(*) FROM public.intake_items intake JOIN public.upload_sessions session ON session.id=intake.upload_session_id
      WHERE intake.org_id=v_org_id AND session.declared_filename IN ('release-global-intake.pdf','release-matter-origin.pdf') AND intake.state='assigned')<>2
    OR (SELECT count(*) FROM public.intake_items intake JOIN public.upload_sessions session ON session.id=intake.upload_session_id
      WHERE intake.org_id=v_org_id AND session.declared_filename='release-global-intake.pdf' AND intake.intended_matter_id IS NULL)<>1
    OR (SELECT count(*) FROM public.intake_items intake JOIN public.upload_sessions session ON session.id=intake.upload_session_id
      WHERE intake.org_id=v_org_id AND session.declared_filename='release-matter-origin.pdf' AND intake.intended_matter_id=v_primary_matter)<>1 THEN
    RAISE EXCEPTION 'Canonical global/Matter Intake origin state is incorrect';
  END IF;
  IF (SELECT count(*) FROM public.document_versions version JOIN public.upload_sessions session ON session.asset_id=version.asset_id
      JOIN public.documents document ON document.id=version.document_id AND document.current_version_id=version.id
      JOIN public.intake_item_assignments assignment ON assignment.document_version_id=version.id AND assignment.document_id=document.id
      WHERE document.org_id=v_org_id AND document.matter_id=v_primary_matter AND session.declared_filename IN ('release-global-intake.pdf','release-matter-origin.pdf')
        AND version.version_number=1 AND version.state='current')<>2 THEN RAISE EXCEPTION 'Exact source/version/assignment lineage duplicated or missing'; END IF;
  SELECT review.id INTO STRICT v_recovery_item FROM public.review_items review
    JOIN public.document_versions version ON version.id=review.document_version_id
    JOIN public.upload_sessions session ON session.asset_id=version.asset_id
    WHERE review.org_id=v_org_id AND session.declared_filename='release-matter-origin.pdf'
      AND review.type='processing_recovery' AND review.status='closed';
  IF (SELECT count(*) FROM public.document_field_candidates WHERE manual_review_item_id=v_recovery_item AND origin_kind='manual_recovery')<>5
    OR (SELECT count(*) FROM public.review_item_decisions WHERE review_item_id=v_recovery_item AND actor_user_id=v_owner_id)<>1
    OR (SELECT count(*) FROM public.activity_events WHERE correlation_id=v_recovery_item AND actor_id=v_owner_id AND event_type='review.processing_recovery_decided')<>1 THEN
    RAISE EXCEPTION 'Manual recovery decisions or Activity identity are not exact';
  END IF;
  SELECT review.id INTO STRICT v_global_item FROM public.review_items review JOIN public.intake_items intake ON intake.id=review.intake_id
    JOIN public.upload_sessions session ON session.id=intake.upload_session_id
    WHERE session.declared_filename='release-global-intake.pdf' AND review.type='ambiguous_placement' AND review.status='closed';
  IF (SELECT count(*) FROM public.review_item_decisions WHERE review_item_id=v_global_item AND actor_user_id=v_owner_id)<>1
    OR (SELECT count(*) FROM public.intake_placement_decisions WHERE review_item_id=v_global_item AND actor_user_id=v_owner_id)<>1
    OR (SELECT count(*) FROM public.activity_events WHERE correlation_id=v_global_item AND actor_id=v_owner_id AND event_type='review.ambiguous_placement_decided')<>1 THEN
    RAISE EXCEPTION 'Placement decisions or Activity identity are not exact';
  END IF;
  IF (SELECT count(*) FROM public.document_relationships relationship WHERE relationship.org_id=v_org_id AND relationship.matter_id=v_primary_matter AND relationship.lifecycle_state='active' AND relationship.verification='human')<>1 THEN
    RAISE EXCEPTION 'Truthful read-only graph relationship is missing or duplicated';
  END IF;
  IF (SELECT count(*) FROM public.deadlines deadline WHERE deadline.org_id=v_org_id AND deadline.matter_id=v_primary_matter AND deadline.origin='manual' AND deadline.verification_state='verified' AND deadline.lifecycle='open')<>1 THEN
    RAISE EXCEPTION 'Manually verified deadline is missing or duplicated';
  END IF;
  IF EXISTS(SELECT 1 FROM public.outbox_events WHERE aggregate_id IN (
      SELECT document.id FROM public.documents document JOIN public.document_versions version ON version.document_id=document.id
      JOIN public.upload_sessions session ON session.asset_id=version.asset_id
      WHERE session.declared_filename='release-matter-origin.pdf') AND payload->>'scope'='extract' AND created_at>(SELECT created_at FROM public.review_items WHERE id=v_recovery_item)) THEN
    RAISE EXCEPTION 'Manual recovery enqueued a duplicate extraction side effect';
  END IF;
END $journey$;
SELECT 'Release journey cross-feature SQL assertions passed.';
`

const signupDiagnostic = String.raw`
SELECT jsonb_build_object(
  'matching_auth_users',(SELECT count(*) FROM auth.users WHERE email='${ownerEmail}'),
  'matching_identities',(SELECT count(*) FROM auth.identities WHERE identity_data->>'email'='${ownerEmail}'),
  'confirmed_users',(SELECT count(*) FROM auth.users WHERE email='${ownerEmail}' AND email_confirmed_at IS NOT NULL),
  'matching_profiles',(SELECT count(*) FROM public.user_profiles profile JOIN auth.users users ON users.id=profile.user_id WHERE users.email='${ownerEmail}')
);
`

if (operation === 'prepare') process.stdout.write(`${sql(prepare, { tuples: true })}\n`)
else if (operation === 'activate-relationship') process.stdout.write(`${sql(activate)}\n`)
else if (operation === 'verify') process.stdout.write(`${sql(verify)}\n`)
else if (operation === 'signup-diagnostic') process.stdout.write(`${sql(signupDiagnostic, { tuples: true })}\n`)
else throw new Error('Use prepare, activate-relationship, verify, or signup-diagnostic.')
