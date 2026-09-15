import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const root = process.cwd()
const workdir = mkdtempSync(join(tmpdir(), 'dms-processing-source-166.'))
const project = 'dms-processing-source-166'
const container = `supabase_db_${project}`
const cli = join(root, 'node_modules/supabase/dist/supabase.js')
const lockPath = join(tmpdir(), `${project}.lock`)
let owned = false
let locked = false
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024, env: { ...process.env, DO_NOT_TRACK: '1' }, ...options })
  if (result.error || result.status !== 0) throw new Error(`${command}: ${result.error?.message ?? result.stderr}\n${result.stdout}`)
  return result.stdout
}
try {
  mkdirSync(lockPath)
  locked = true
  const existing = run('docker', ['ps', '-a', '--format', '{{.Names}}'])
  if (existing.split('\n').some(name => name.endsWith(`_${project}`))) throw new Error('Disposable processing-source project is already owned; no existing resource changed.')
  const occupied = spawnSync('lsof', ['-nP', '-iTCP:56620-56627', '-sTCP:LISTEN'], { encoding: 'utf8' })
  if (occupied.error || (occupied.status !== 0 && occupied.status !== 1)) throw new Error('Could not verify processing-source acceptance ports.')
  if (occupied.stdout.trim()) throw new Error('Processing-source acceptance ports are in use; no existing resource changed.')
  cpSync(join(root, 'supabase/migrations'), join(workdir, 'supabase/migrations'), { recursive: true })
  writeFileSync(join(workdir, 'supabase/config.toml'), `project_id = "${project}"
[api]
port = 56621
schemas = ["public", "graphql_public"]
[db]
port = 56622
shadow_port = 56620
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 56623
[local_smtp]
enabled = true
port = 56624
[auth]
site_url = "http://127.0.0.1:3116"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 56627
`)
  owned = true
  console.log(`Replaying all migrations in isolated ${project}.`)
  run(node, [cli, 'start', '--workdir', workdir])
  const lint = run(node, [cli, 'db', 'lint', '--local', '--workdir', workdir, '--level', 'error'])
  if (JSON.parse(lint).results?.length) throw new Error('Disposable database lint found errors.')
  console.log('Error-level database lint passed.')
  if (process.argv.includes('--types')) {
    const typeRoot = mkdtempSync(join(tmpdir(), 'dms-processing-source-types.'))
    const args = ['scripts/generate-supabase-types.mjs', '--local', '--workdir', workdir]
    try {
      cpSync(join(root, 'scripts/generate-supabase-types.mjs'), join(typeRoot, 'scripts/generate-supabase-types.mjs'), { recursive: true })
      cpSync(join(root, 'scripts/refine-supabase-types.mjs'), join(typeRoot, 'scripts/refine-supabase-types.mjs'), { recursive: true })
      cpSync(join(root, 'src/lib/supabase/database.types.ts'), join(typeRoot, 'src/lib/supabase/database.types.ts'), { recursive: true })
      symlinkSync(resolve(root, 'node_modules'), join(typeRoot, 'node_modules'), 'dir')
      const options = { cwd: typeRoot, env: { ...process.env, DO_NOT_TRACK: '1', PATH: `${join(root, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` } }
      run(node, args, options)
      const first = readFileSync(join(typeRoot, 'src/lib/supabase/database.types.ts'), 'utf8')
      const checkedIn = readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')
      if (first !== checkedIn) {
        const generatedLines = first.split('\n'), checkedLines = checkedIn.split('\n')
        const firstDifference = generatedLines.findIndex((line, index) => line !== checkedLines[index])
        throw new Error(`Generated types differ from checked-in types near line ${firstDifference + 1}: generated ${JSON.stringify(generatedLines.slice(firstDifference, firstDifference + 8))}; checked-in ${JSON.stringify(checkedLines.slice(firstDifference, firstDifference + 8))}`)
      }
      run(node, args, options)
      if (first !== readFileSync(join(typeRoot, 'src/lib/supabase/database.types.ts'), 'utf8')) throw new Error('Repeated generated types parity failed.')
      console.log('Generated database types: checked-in and repeated parity.')
    } finally { rmSync(typeRoot, { recursive: true, force: true }) }
  }
  const fixture = readFileSync(join(root, 'supabase/tests/document_processing_source_grant.sql'), 'utf8')
  console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: fixture }))
  if (process.argv.includes('--copy')) {
    const copyFixture = readFileSync(join(root, 'supabase/tests/document_processing_source_copy_compatibility.sql'), 'utf8')
    console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: copyFixture }))
  }
  if (process.argv.includes('--concurrency')) {
    const setup = readFileSync(join(root, 'supabase/tests/document_processing_source_concurrency_setup.sql'), 'utf8')
    console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: setup }))
    console.log(run('bash', ['supabase/tests/document_processing_source_concurrency.sh'], { env: { ...process.env, DO_NOT_TRACK: '1', SUPABASE_DB_CONTAINER: container } }))
  }
} finally {
  let cleaned = !owned
  if (owned) {
    const stopped = spawnSync(node, [cli, 'stop', '--no-backup', '--workdir', workdir], { encoding: 'utf8', env: { ...process.env, DO_NOT_TRACK: '1' } })
    if (stopped.status !== 0) console.error(`Cleanup failed: inspect exclusively owned ${project} at ${workdir}.`)
    else { cleaned = true; console.log('Removed exclusively owned processing-source stack and data.') }
  }
  if (cleaned) rmSync(workdir, { recursive: true, force: true })
  if (locked && cleaned) rmSync(lockPath, { recursive: true, force: true })
}
