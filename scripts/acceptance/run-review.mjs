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
  const sqlConflict=process.argv.includes('--sql-conflict')
  if(browserConflict){
    for(const file of ['document_boundary_repair_setup.sql','placed_document_identity_conflict_browser_setup.sql']){
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
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.review.config.ts','--grep','placed document conflict'],{
      env:{...process.env,REVIEW_ACCEPTANCE_WORKDIR:workdir}
    }))
  } else if(sqlConflict){
    for(const file of ['document_boundary_repair_setup.sql','placed_document_identity_conflict_review.sql']){
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
