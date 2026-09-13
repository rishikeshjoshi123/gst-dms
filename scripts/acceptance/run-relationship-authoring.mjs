import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const root = process.cwd()
const workdir = mkdtempSync(join(tmpdir(), 'dms-relationship-authoring-acceptance.'))
const project = 'dms-relationship-authoring-155'
const container = `supabase_db_${project}`
const cli = join(root, 'node_modules/supabase/dist/supabase.js')
let owned = false
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024, ...options })
  if (result.error || result.status !== 0) throw new Error(`${command}: ${result.error?.message ?? result.stderr}\n${result.stdout}`)
  return result.stdout
}
try {
  const existing = run('docker', ['ps', '-a', '--format', '{{.Names}}'])
  if (existing.split('\n').some(name => name.endsWith(`_${project}`))) throw new Error('Disposable project name is already owned; no existing resource changed.')
  cpSync(join(root, 'supabase/migrations'), join(workdir, 'supabase/migrations'), { recursive: true })
  writeFileSync(join(workdir, 'supabase/config.toml'), `project_id = "${project}"
[api]
port = 57321
schemas = ["public", "graphql_public"]
[db]
port = 57322
shadow_port = 57320
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 57323
[local_smtp]
enabled = true
port = 57324
[auth]
site_url = "http://127.0.0.1:3105"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 57327
`)
  console.log(`Isolated ${project}: API 57321, DB 57322, shadow 57320; ${workdir}`)
  owned = true
  run(node, [cli, 'start', '--workdir', workdir])
  const lint = run(node, [cli, 'db', 'lint', '--local', '--workdir', workdir, '--level', 'error'])
  console.log(lint)
  if (JSON.parse(lint).results?.length) throw new Error('Disposable database lint found errors.')
  if (process.argv.includes('--types')) {
    const args = ['scripts/generate-supabase-types.mjs', '--local', '--workdir', workdir]
    const options = { env: { ...process.env, PATH: `${join(root, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` } }
    run(node, args, options)
    const first = readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')
    run(node, args, options)
    if (first !== readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')) throw new Error('Types generation parity failed')
    console.log('Generated types: exact repeated parity.')
  }
  for (const file of ['supabase/tests/effective_relationship_core.sql', 'supabase/tests/timeline_relationship_authoring.sql', ...(process.argv.includes('--browser') ? ['scripts/acceptance/seed.sql'] : [])]) {
    console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, file), 'utf8') }))
  }
  if (process.argv.includes('--build')) console.log(run(node, ['scripts/acceptance/start-relationship-authoring-server.mjs', '--build'], { env: { ...process.env, RELATIONSHIP_AUTHORING_ACCEPTANCE_WORKDIR: workdir } }))
  if (process.argv.includes('--browser')) console.log(run(node, ['node_modules/@playwright/test/cli.js', 'test', '--config', 'playwright.relationship-authoring.config.ts'], { env: { ...process.env, RELATIONSHIP_AUTHORING_ACCEPTANCE_WORKDIR: workdir } }))
} finally {
  let cleaned = !owned
  if (owned) {
    const stopped = spawnSync(node, [cli, 'stop', '--no-backup', '--workdir', workdir], { encoding: 'utf8' })
    if (stopped.status !== 0) console.error(`Cleanup failed: inspect exclusively owned ${project}; retained recovery config ${workdir}.`)
    else { cleaned = true; console.log('Removed exclusively owned relationship-authoring stack and data.') }
  }
  if (cleaned) rmSync(workdir, { recursive: true, force: true })
}
