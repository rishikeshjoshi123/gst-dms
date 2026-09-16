import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const root = process.cwd()
const workdir = mkdtempSync(join(tmpdir(), 'dms-review-acceptance.'))
const cli = join(root, 'node_modules/supabase/dist/supabase.js')
const container = 'supabase_db_dms-review-153'
let createdProject = false
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024, ...options })
  if (result.status !== 0 && args.includes('node_modules/@playwright/test/cli.js')) console.error(result.stdout)
  if (result.error || result.status !== 0) throw new Error(`${command} failed: ${result.error?.message ?? `${result.stderr}\n${result.stdout}`}`)
  return result.stdout
}
try {
  const existing = run('docker', ['ps', '-a', '--format', '{{.Names}}'])
  if (existing.split('\n').some(name => name.endsWith('_dms-review-153'))) throw new Error('The isolated Review project name is already owned by another run. No existing resource was changed.')
  cpSync(join(root, 'supabase/migrations'), join(workdir, 'supabase/migrations'), { recursive: true })
  writeFileSync(join(workdir, 'supabase/config.toml'), `project_id = "dms-review-153"
[api]
port = 55321
schemas = ["public", "graphql_public"]
[db]
port = 55322
shadow_port = 55320
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 55323
[local_smtp]
enabled = true
port = 55324
[auth]
site_url = "http://127.0.0.1:3103"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 55327
`)
  console.log(`Replaying migrations in isolated dms-review-153 on database port 55322 (${workdir}).`)
  createdProject = true
  run(node, [cli, 'start', '--workdir', workdir])
  console.log(run(node, [cli, 'db', 'lint', '--local', '--workdir', workdir, '--level', 'error']))
  if (process.argv.includes('--types')) {
    run(node, ['scripts/generate-supabase-types.mjs', '--local', '--workdir', workdir], { env: { ...process.env, PATH: `${join(root, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` } })
    const generatedTypes = readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')
    run(node, ['scripts/generate-supabase-types.mjs', '--local', '--workdir', workdir], { env: { ...process.env, PATH: `${join(root, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` } })
    if (readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8') !== generatedTypes) throw new Error('Isolated database type generation is not deterministic.')
    console.log('Regenerated and refined database types; repeated generation has exact parity.')
  }
  const browserConflict=process.argv.includes('--browser-conflict')
  const browserMulti=process.argv.includes('--browser-multi')
  const sqlConflict=process.argv.includes('--sql-conflict')
  const sqlMulti=process.argv.includes('--sql-multi')
  const sqlDuplicate=process.argv.includes('--sql-duplicate')
  const browserDuplicate=process.argv.includes('--browser-duplicate')
  const browserGroup=process.argv.includes('--browser-group')
  const probeDuplicate=process.argv.includes('--probe-duplicate')
  const stabilisation=process.argv.includes('--stabilisation')
  const relationship=process.argv.includes('--relationship')
  const browserRelationship=process.argv.includes('--browser-relationship')
  if(browserRelationship){
    let input=readFileSync(join(root,'supabase/tests/document_reference_exact_resolution_concurrency_setup.sql'),'utf8')
    const old="repeat(i::text,64),100"
    if(!input.includes(old)) throw new Error('Relationship browser source assets changed; reconcile exact synthetic bytes.')
    input=input.replace(old,`CASE i WHEN 1 THEN 'f469b1e2a159150fa5e152951b804e34d0255930f582a22f041d435cddcabe24' ELSE '5c5f5fc27a7f710c694ca9aa9e3afe54cf7b0254a2465d440d62fb13a154fdbd' END,CASE i WHEN 1 THEN 1967 ELSE 1977 END`)
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input}))
    const browserSetup=`DO $$ BEGIN
      UPDATE auth.users SET encrypted_password=crypt('RelationshipFixture173!',gen_salt('bf')),
        raw_app_meta_data='{"provider":"email","providers":["email"]}',confirmation_token='',recovery_token='',email_change_token_new='',email_change=''
        WHERE id='151a0000-0000-0000-0000-000000000099';
      INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at)
        SELECT u.id::text,u.id,jsonb_build_object('sub',u.id,'email',u.email),'email',gen_random_uuid(),now(),now(),now()
        FROM auth.users u WHERE u.id='151a0000-0000-0000-0000-000000000099';
      IF (SELECT count(*) FROM public.review_items WHERE type='relationship_suggestion' AND status='needs_review')<>1 THEN
        RAISE EXCEPTION 'relationship browser candidate was not produced';
      END IF;
    END $$;`
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:browserSetup}))
    console.log(run(node,['scripts/acceptance/seed-review-storage.mjs'],{env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir,REVIEW_ACCEPTANCE_RELATIONSHIP_ONLY:'1'}}))
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.review.config.ts','--grep','exact reference relationship'],{env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}}))
    if(process.argv.includes('--build')) console.log(run(node,['scripts/acceptance/start-review-server.mjs','--build'],{env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}}))
  } else if(relationship){
    const exact=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/document_reference_exact_resolution.sql'),'utf8')})
    console.log(`document_reference_exact_resolution.sql: ${exact.trim()}`)
    const setup=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/document_reference_exact_resolution_concurrency_setup.sql'),'utf8')})
    console.log(`document_reference_exact_resolution_concurrency_setup.sql: ${setup.trim()}`)
    console.log(run('bash',['supabase/tests/relationship_suggestion_review_concurrency.sh'],{env:{...process.env,SUPABASE_DB_CONTAINER:container}}))
  } else if(browserConflict||browserMulti){
    for(const file of ['document_boundary_repair_setup.sql',browserMulti?'multi_placed_document_identity_conflict_browser_setup.sql':'placed_document_identity_conflict_browser_setup.sql']){
      let input=readFileSync(join(root,'supabase/tests',file),'utf8')
      if(file==='document_boundary_repair_setup.sql'){
        const old='lpad(i::text,64,i::text),100'
        if(!input.includes(old)) throw new Error('Source fixture asset INSERT changed; browser byte provenance must be reconciled.')
        input=input.replace(old,`CASE i WHEN 1 THEN 'f469b1e2a159150fa5e152951b804e34d0255930f582a22f041d435cddcabe24' WHEN 2 THEN '5c5f5fc27a7f710c694ca9aa9e3afe54cf7b0254a2465d440d62fb13a154fdbd' ELSE lpad(i::text,64,i::text) END,CASE i WHEN 1 THEN 1967 WHEN 2 THEN 1977 ELSE 100 END`)
      }
      const output=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input})
      console.log(`${file}: ${output.trim()}`)
    }
    console.log(run(node,['scripts/acceptance/seed-review-storage.mjs'],{
      env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir,REVIEW_ACCEPTANCE_CONFLICT_ONLY:'1'}
    }))
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.review.config.ts','--grep',browserMulti?'multiple filed Matter conflicts':'placed document conflict'],{
      env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}
    }))
  } else if(stabilisation){
    const output=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],
      {input:readFileSync(join(root,'supabase/tests/document_boundary_repair_setup.sql'),'utf8')})
    console.log(`document_boundary_repair_setup.sql: ${output.trim()}`)
    console.log(run(node,['scripts/acceptance/placed-document-review-stabilisation.mjs'],
      {env:{...process.env,SUPABASE_DB_CONTAINER:container}}))
  } else if(browserDuplicate||browserGroup||probeDuplicate){
    let input=readFileSync(join(root,'supabase/tests/document_boundary_repair_setup.sql'),'utf8')
    const old='lpad(i::text,64,i::text),100'
    if(!input.includes(old)) throw new Error('Source fixture asset INSERT changed; reconcile exact browser bytes.')
    input=input.replace(old,`CASE i WHEN 1 THEN 'f469b1e2a159150fa5e152951b804e34d0255930f582a22f041d435cddcabe24' WHEN 2 THEN '5c5f5fc27a7f710c694ca9aa9e3afe54cf7b0254a2465d440d62fb13a154fdbd' ${browserGroup?"WHEN 3 THEN '98f3adb999f6ebe3cafa007bc8afa65454f245ad269178e2d1d4e9c47ef92307'":''} ELSE lpad(i::text,64,i::text) END,CASE i WHEN 1 THEN 1967 WHEN 2 THEN 1977 ${browserGroup?'WHEN 3 THEN 1991':''} ELSE 100 END`)
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input}))
    const browserSetup=`DO $$ DECLARE actor uuid:='152a0000-0000-0000-0000-000000000001'; candidate_id uuid; rev bigint; result record; BEGIN
      UPDATE auth.users SET encrypted_password=crypt('PlacementFixture167!',gen_salt('bf')),
        raw_app_meta_data='{"provider":"email","providers":["email"]}',confirmation_token='',recovery_token='',email_change_token_new='',email_change=''
        WHERE id IN (actor,'152a0000-0000-0000-0000-000000000002'::uuid);
      INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at)
        SELECT u.id::text,u.id,jsonb_build_object('sub',u.id,'email',u.email),'email',gen_random_uuid(),now(),now(),now()
        FROM auth.users u WHERE u.id IN (actor,'152a0000-0000-0000-0000-000000000002'::uuid);
      PERFORM set_config('request.jwt.claim.role','authenticated',true);
      PERFORM set_config('request.jwt.claim.sub',actor::text,true);
      PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor,'iat',extract(epoch FROM now())::bigint)::text,true);
      FOR candidate_id IN SELECT id FROM public.document_field_candidates WHERE document_id IN ('152e0000-0000-0000-0000-000000000001'::uuid,'152e0000-0000-0000-0000-000000000002'::uuid${browserGroup?",'152e0000-0000-0000-0000-000000000003'::uuid":''})
        AND field_path='document.official_reference.self_identifier' AND normalized_value->>'normalized_value'='GST/555/2026'
        ORDER BY document_id LOOP
        SELECT lifecycle_revision INTO rev FROM public.documents WHERE id=(SELECT document_id FROM public.document_field_candidates WHERE id=candidate_id);
        SELECT * INTO result FROM public.activate_document_self_identifier(candidate_id,rev,NULL,gen_random_uuid());
        IF result.code<>'ok' THEN RAISE EXCEPTION 'duplicate browser activation failed: %',result.code; END IF;
      END LOOP;
      IF (SELECT count(*) FROM public.review_items WHERE type='possible_duplicate' AND status='needs_review')<>1
        OR (SELECT count(*) FROM public.possible_duplicate_sources WHERE review_item_id=(SELECT id FROM public.review_items WHERE type='possible_duplicate' AND status='needs_review'))<>${browserGroup?3:2}
        THEN RAISE EXCEPTION 'browser ${browserGroup?'group':'pair'} was not produced'; END IF;
    END $$;`
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:browserSetup}))
    console.log(run(node,['scripts/acceptance/seed-review-storage.mjs'],
      {env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir,REVIEW_ACCEPTANCE_CONFLICT_ONLY:'1',REVIEW_ACCEPTANCE_GROUP:browserGroup?'1':'0'}}))
    if(probeDuplicate){
      const probe=`BEGIN;SET LOCAL request.jwt.claim.role='authenticated';SET LOCAL request.jwt.claim.sub='152a0000-0000-0000-0000-000000000002';
        SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"152a0000-0000-0000-0000-000000000002"}';
        SELECT items,total_count,can_resolve FROM public.read_review_queue('needs_review','possible_duplicate','all','',1,25);
        SELECT public.read_review_detail((SELECT id FROM public.review_items WHERE type='possible_duplicate' AND status='needs_review' LIMIT 1));ROLLBACK;`
      console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:probe}))
      console.log(run(node,['scripts/acceptance/probe-possible-duplicate.mjs'],{env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}}))
    }else
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.review.config.ts','--grep',browserGroup?'grouped possible duplicate exact PDF comparison':'possible duplicate exact PDF comparison records both interpretations'],
      {env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}}))
  } else if(sqlDuplicate){
    const file='document_reference_exact_resolution.sql'
    const output=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],
      {input:readFileSync(join(root,'supabase/tests',file),'utf8')})
    console.log(`${file}: ${output.trim()}`)
  } else if(sqlConflict||sqlMulti){
    for(const file of ['document_boundary_repair_setup.sql',sqlMulti?'multi_placed_document_identity_conflict_review.sql':'placed_document_identity_conflict_review.sql']){
      const output=run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests',file),'utf8')})
      console.log(`${file}: ${output.trim()}`)
    }
  } else {
  for (const file of ['extraction_conflict_review_setup.sql', 'document_boundary_repair_setup.sql', 'placed_document_identity_conflict_review.sql', 'extraction_conflict_review.sql', 'extraction_conflict_review_lifecycle.sql', 'processing_recovery_review.sql', 'ambiguous_intake_placement_review.sql', 'ambiguous_intake_placement_stale_facts.sql']) {
    const output = run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, 'supabase/tests', file), 'utf8') })
    console.log(`${file}: ${output.trim()}`)
  }
  console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, 'supabase/tests/ambiguous_intake_placement_concurrency_setup.sql'), 'utf8') }))
  console.log(run('sh', ['supabase/tests/ambiguous_intake_placement_concurrency.sh'], { env: { ...process.env, SUPABASE_DB_CONTAINER: container } }))
  console.log(run('bash', ['supabase/tests/extraction_conflict_review_concurrency.sh'], { env: { ...process.env, SUPABASE_DB_CONTAINER: container } }))
  console.log(run(node, ['scripts/acceptance/review-finisher-concurrency.mjs'], { env: { ...process.env, SUPABASE_DB_CONTAINER: container } }))
  const probeDate = process.argv.includes('--probe-date')
  const browserDate = process.argv.includes('--browser-date') || probeDate
  const browserRequested = process.argv.includes('--browser') || process.argv.includes('--browser-recovery') || process.argv.includes('--browser-placement') || browserDate
  if (browserRequested && !browserDate) console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, 'supabase/tests/ambiguous_intake_placement_browser_setup.sql'), 'utf8') }))
  if (browserRequested && !browserDate) console.log(run(node, ['node_modules/tsx/dist/cli.mjs', 'scripts/acceptance/produce-review-placement.mts'], { env: { ...process.env, NODE_OPTIONS: '--conditions=react-server', NODE_PATH: `${join(root, 'node_modules/next/dist/compiled')}${process.env.NODE_PATH ? `:${process.env.NODE_PATH}` : ''}`, NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:55321', SUPABASE_SERVICE_ROLE_KEY: JSON.parse(run(node, [cli, 'status', '--workdir', workdir, '-o', 'json'])).SERVICE_ROLE_KEY } }))
  if (browserRequested && !browserDate) console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, 'supabase/tests/ambiguous_intake_placement_browser_invalidate.sql'), 'utf8') }))
  if (browserDate) console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, 'supabase/tests/explicit_due_date_browser_setup.sql'), 'utf8') }))
  if (browserRequested) console.log(run(node, ['scripts/acceptance/seed-review-storage.mjs'], { env: { ...process.env, REVIEW_ACCEPTANCE_WORKDIR: workdir, REVIEW_ACCEPTANCE_DATE_ONLY: browserDate ? '1' : '0' } }))
  if (probeDate) console.log(run(node,['scripts/acceptance/probe-explicit-due-rpc.mjs'],{
    env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}
  }))
  if (browserRequested && !probeDate) {
    const browserArgs = ['node_modules/@playwright/test/cli.js', 'test', '--config', 'playwright.review.config.ts']
    if (process.argv.includes('--browser-recovery')) browserArgs.push('--grep', 'responsive processing recovery')
    if (process.argv.includes('--browser-placement')) browserArgs.push('--grep', 'trusted ambiguous global Intake')
    if (browserDate) browserArgs.push('--grep', 'exact legal date')
    console.log(run(node, browserArgs, { env: { ...process.env, REVIEW_ACCEPTANCE_WORKDIR: workdir } }))
  }
  if (process.argv.includes('--build')) console.log(run(node, ['scripts/acceptance/start-review-server.mjs', '--build'], { env: { ...process.env, REVIEW_ACCEPTANCE_WORKDIR: workdir } }))
  }
} finally {
  if (createdProject) {
    const stopped = spawnSync(node, [cli, 'stop', '--no-backup', '--workdir', workdir], { encoding: 'utf8' })
    if (stopped.status !== 0) console.error('Disposable Review cleanup failed; inspect project dms-review-153.')
    else console.log('Removed the exclusively owned disposable Review stack and data.')
  }
  rmSync(workdir, { recursive: true, force: true })
}
