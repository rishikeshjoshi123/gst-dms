-- Provider-neutral fixture: two competing runs for one exact semantic fact.
\set ON_ERROR_STOP on
DO $fixture$
DECLARE actor uuid:='153a0000-0000-0000-0000-000000000001'; org uuid:='153b0000-0000-0000-0000-000000000001';
  client uuid:='153c0000-0000-0000-0000-000000000001'; matter uuid:='153d0000-0000-0000-0000-000000000001';
  doc uuid; asset uuid; version uuid; processing uuid; run uuid; lease uuid; source_lease uuid;
  i integer; j integer; user_id uuid; candidate jsonb; finished record; state text; outcome text; review_required boolean;
BEGIN
  FOR i IN 1..7 LOOP
    user_id:=('153a0000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
      VALUES('00000000-0000-0000-0000-000000000000',user_id,'authenticated','authenticated','review-'||i||'@example.test',crypt('ReviewFixture153!',gen_salt('bf')),now(),'{}','{}',now(),now());
    UPDATE auth.users u SET confirmation_token='',recovery_token='',email_change_token_new='',email_change='',raw_app_meta_data='{"provider":"email","providers":["email"]}',raw_user_meta_data='{"full_name":"Review member"}' WHERE u.id=user_id;
    INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at)
      VALUES(user_id::text,user_id,jsonb_build_object('sub',user_id,'email','review-'||i||'@example.test'),'email',gen_random_uuid(),now(),now(),now());
  END LOOP;
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Review acceptance',actor),('153b0000-0000-0000-0000-000000000002','Foreign Review','153a0000-0000-0000-0000-000000000005');
  INSERT INTO public.org_members(org_id,user_id,role) VALUES
    (org,'153a0000-0000-0000-0000-000000000002','admin'),(org,'153a0000-0000-0000-0000-000000000003','associate'),
    (org,'153a0000-0000-0000-0000-000000000004','viewer'),(org,'153a0000-0000-0000-0000-000000000006','associate');
  UPDATE public.organisation_memberships membership SET state='suspended',suspended_at=now(),suspended_by=actor,suspension_reason='Fixture suspension' WHERE membership.user_id='153a0000-0000-0000-0000-000000000006';
  INSERT INTO public.clients(id,org_id,name) VALUES(client,org,'Review client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(matter,org,client,'Review proceeding','REVIEW-153');
  FOR i IN 1..9 LOOP
    doc:=('153e0000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    asset:=('153f0000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    version:=('15300000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,content_availability,status,created_by)
      VALUES(doc,org,matter,'fixture/review-'||i||'.pdf','Review source '||i||CASE WHEN i=6 THEN ' · '||repeat('long-identifier-',14) ELSE '' END,'proceeding','upload','source_attached','placed',actor);
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
      VALUES(asset,org,'documents','orgs/'||org||'/assets/'||asset||'/original.pdf',CASE WHEN i=1 THEN 'e5ed1b9997d8267aea013af774223c8785d9c8802f642a6adc2e6ad33b7af113' ELSE md5(doc::text)||md5(doc::text) END,CASE WHEN i=1 THEN 4530 ELSE 100 END,'application/pdf','available',now(),CASE WHEN i=1 THEN 4 ELSE 2 END,actor);
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
      VALUES(version,org,doc,asset,1,'review-'||i||'.pdf',CASE WHEN i=1 THEN 4 ELSE 2 END,'valid','current',now(),now(),actor);
    UPDATE public.documents SET current_version_id=version WHERE id=doc;
    FOR j IN 1..CASE WHEN i<=2 OR i IN (7,8) THEN 2 ELSE 1 END LOOP
      processing:=gen_random_uuid(); run:=gen_random_uuid(); lease:=gen_random_uuid(); source_lease:=gen_random_uuid();
      INSERT INTO public.document_processing_runs(id,org_id,document_id,document_version_id,scope,idempotency_key,state,stage,started_at,lease_token,lease_expires_at,heartbeat_at)
        VALUES(processing,org,doc,version,'full','fixture.review.'||processing,'running','extracting',now(),lease,now()+interval '10 minutes',now());
      INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at,attempt_count,lease_token,lease_expires_at,heartbeat_at)
        VALUES(run,org,asset,'ai_extraction.'||processing,'ai_extraction.'||processing,'ai_extraction','running','running','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now(),1,source_lease,now()+interval '10 minutes',now());
      INSERT INTO public.source_analysis_attempts(org_id,source_analysis_run_id,attempt_number,state,retry_reason,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,started_at)
        VALUES(org,run,1,'running','initial','vertex-ai','gemini-2.5-flash','fixture-model','v4.0','document-extraction-v4','gst-legal-material-observation-catalogue-v3','typed-material-observation-normalizer-v3',now());
      INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
        VALUES(org,doc,version,processing,run,'ready',CASE WHEN i=1 THEN 4 ELSE 2 END,repeat('a',64))
        ON CONFLICT(org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id,source_analysis_run_id=EXCLUDED.source_analysis_run_id;
      INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages)
        SELECT org,id,n,'SCN and OIO source observations. Tax period JAN 2020'||CASE WHEN i=6 THEN repeat(' supporting-source-observation',15) ELSE '' END,'[]','[]',repeat('a',64),'native_pdf','native-pdf-quality-v1','{}','{}' FROM public.document_page_text_artifacts CROSS JOIN generate_series(1,CASE WHEN i=1 THEN 4 ELSE 2 END) n WHERE source_analysis_run_id=run ON CONFLICT DO NOTHING;
      state:=CASE WHEN i IN(3,6) THEN 'conflicting' WHEN i=4 THEN 'provisional' ELSE 'eligible' END;
      review_required:=j=2 OR i IN(3,4,5,6,9); outcome:=CASE WHEN i=5 THEN 'invalid_model_output' WHEN i=9 THEN 'provider_failed' ELSE 'validated' END;
      candidate:=jsonb_build_array(jsonb_build_object('semantic_candidate_key','document.type','field_path','document.type','value_type','code','normalized_value',CASE WHEN j=1 THEN 'SCN' ELSE 'OIO' END,'page_number',j,'quotation',CASE WHEN j=1 THEN 'SCN' ELSE 'OIO' END,'evidence_regions',NULL,'confidence',0.99,'validation_state',state,'validation_error_codes',NULL,'verified_source_anchor',NULL));
      IF i=6 THEN candidate:=jsonb_build_array(jsonb_build_object('semantic_candidate_key','tax_period:fixture','field_path','document.tax_period','value_type','structured',
        'normalized_value','{"kind":"month","raw":"JAN 2020","display":"January 2020","precision":"month","segments":[{"kind":"month","month":"2020-01","quarter":null,"financial_year":null,"start_date":null,"end_date":null}],"financial_years":["2019-20"],"printed_financial_years":["2020-21"],"derived_financial_years":["2019-20"],"conflict":true,"catalogue_version":"gst-legal-material-observation-catalogue-v3","normalizer_version":"typed-material-observation-normalizer-v3"}'::jsonb,
        'page_number',1,'quotation','Tax period JAN 2020'||repeat(' supporting-source-observation',15),'evidence_regions',NULL,'confidence',0.99,'validation_state','conflicting','validation_error_codes',NULL,'verified_source_anchor',jsonb_build_object('char_start',33,'char_end',52+length(repeat(' supporting-source-observation',15)),'token_start',NULL,'token_end',NULL,'table_cell',NULL))); END IF;
      SELECT * INTO finished FROM public.finish_document_processing_ai_extraction(processing,lease,run,source_lease,outcome,1,1,1,CASE WHEN i IN (5,9) THEN '[]'::jsonb ELSE candidate END,review_required,jsonb_build_object('doc_type','SCN','reference_number',NULL,'doc_date',NULL,'direction',NULL,'issued_by',NULL,'financial_years','[]'::jsonb,'summary','Fixture','prompt_version','v4.0'));
      IF i NOT IN (5,9) AND finished.binding_id IS NULL THEN RAISE EXCEPTION 'Validated fixture did not materialize: %',finished.code; END IF;
      IF j=1 AND (i<=2 OR i IN (7,8)) AND EXISTS(SELECT 1 FROM public.review_items WHERE document_id=doc) THEN RAISE EXCEPTION 'Clean output created Review'; END IF;
      IF j=1 AND (i<=2 OR i IN (7,8)) AND NOT EXISTS(SELECT 1 FROM public.document_effective_metadata WHERE document_id=doc AND resolution='automatic') THEN RAISE EXCEPTION 'Clean automatic metadata was suppressed'; END IF;
      UPDATE public.document_processing_runs p SET state='completed',stage='ready',completed_at=now(),lease_token=NULL,lease_expires_at=NULL WHERE p.id=processing AND p.state='running';
    END LOOP;
  END LOOP;
  IF (SELECT count(*) FROM public.review_items WHERE org_id=org)<>8 THEN RAISE EXCEPTION 'Expected six extraction conflicts and two processing recovery items'; END IF;
END $fixture$;
