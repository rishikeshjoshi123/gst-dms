import { cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const root = process.cwd()
const workdir = mkdtempSync(join(tmpdir(), 'dms-matter-supporting-files-acceptance.'))
const project = 'dms-matter-supporting-files-156'
const container = `supabase_db_${project}`
const cli = join(root, 'node_modules/supabase/dist/supabase.js')
let owned = false
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024, ...options })
  if (result.error || result.status !== 0) throw new Error(`${command}: ${result.error?.message ?? result.stderr}\n${result.stdout}`)
  return result.stdout
}
try {
  // Safety: verify isolation from supabase_db_dms
  if (container === 'supabase_db_dms') throw new Error('Container name resolves to supabase_db_dms; aborting.')
  const existing = run('docker', ['ps', '-a', '--format', '{{.Names}}'])
  if (existing.split('\n').some(name => name.endsWith(`_${project}`))) throw new Error('Disposable project name is already owned; no existing resource changed.')
  cpSync(join(root, 'supabase/migrations'), join(workdir, 'supabase/migrations'), { recursive: true })
  writeFileSync(join(workdir, 'supabase/config.toml'), `project_id = "${project}"
[api]
port = 57421
schemas = ["public", "graphql_public"]
[db]
port = 57422
shadow_port = 57420
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 57423
[local_smtp]
enabled = true
port = 57424
[auth]
site_url = "http://127.0.0.1:3156"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 57427
`)
  console.log(`Isolated ${project}: API 57421, DB 57422, shadow 57420; ${workdir}`)
  owned = true
  run(node, [cli, 'start', '--workdir', workdir])
  // Verify resolved DB target is NOT supabase_db_dms
  const status = run(node, [cli, 'status', '--workdir', workdir, '-o', 'json'])
  const local = JSON.parse(status)
  const dbUrl = new URL(local.DB_URL)
  if (dbUrl.port === '54322') throw new Error(`Resolved DB port is the default 54322 (supabase_db_dms); aborting.`)
  console.log(`Verified isolated DB port: ${dbUrl.port}`)

  const lint = run(node, [cli, 'db', 'lint', '--local', '--workdir', workdir, '--level', 'error'])
  console.log(lint)
  if (JSON.parse(lint).results?.length) throw new Error('Disposable database lint found errors.')

  // Type generation with exact parity
  if (process.argv.includes('--types') || process.argv.includes('--build')) {
    const args = ['scripts/generate-supabase-types.mjs', '--local', '--workdir', workdir]
    const options = { env: { ...process.env, PATH: `${join(root, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` } }
    run(node, args, options)
    const first = readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')
    run(node, args, options)
    if (first !== readFileSync(join(root, 'src/lib/supabase/database.types.ts'), 'utf8')) throw new Error('Types generation parity failed')
    console.log('Generated types: exact repeated parity.')
  }

  // Run SQL test suites via psql
  for (const file of [
    'supabase/tests/effective_relationship_core.sql',
    'supabase/tests/timeline_relationship_authoring.sql',
    'supabase/tests/matter_supporting_files.sql',
  ]) {
    console.log(`Running ${file}...`)
    console.log(run('docker', ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: readFileSync(join(root, file), 'utf8') }))
  }

  // Production build
  if (process.argv.includes('--build')) {
    console.log('Running production build...')
    const workspace = mkdtempSync(join(tmpdir(), 'dms-matter-supporting-files-app-'))
    try {
      for (const entry of ['src', 'public', 'package.json', 'package-lock.json', 'tsconfig.json', 'next.config.ts', 'postcss.config.mjs']) {
        cpSync(join(root, entry), join(workspace, entry), { recursive: true })
      }
      symlinkSync(resolve(root, 'node_modules'), join(workspace, 'node_modules'), 'dir')
      const fontMock = join(workspace, 'font-mock.cjs')
      writeFileSync(fontMock, `module.exports = new Proxy({}, { get(_target, url) { const mono = String(url).includes('Geist+Mono'); const family = mono ? 'Geist Mono' : 'Geist'; const file = ${JSON.stringify(join(root, 'node_modules/next/dist/next-devtools/server/font/'))} + (mono ? 'geist-mono-latin.woff2' : 'geist-latin.woff2'); return "/* latin */\\n@font-face { font-family: '" + family + "'; font-style: normal; font-weight: 100 900; src: url(" + file + ") format('woff2'); }"; } });`)
      const buildEnv = {
        ...process.env,
        NEXT_PUBLIC_APP_URL: 'http://127.0.0.1:3156',
        NEXT_PUBLIC_SUPABASE_URL: local.API_URL,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: local.ANON_KEY,
        SUPABASE_SERVICE_ROLE_KEY: local.SERVICE_ROLE_KEY,
        TRIGGER_SECRET_KEY: '', TRIGGER_API_URL: 'http://127.0.0.1:9',
        RESEND_API_KEY: 're_acceptance_disabled',
        RESEND_FROM_EMAIL: 'acceptance@invalid.example',
        GOOGLE_APPLICATION_CREDENTIALS: '', GOOGLE_APPLICATION_CREDENTIALS_JSON: '',
        GOOGLE_CLOUD_PROJECT: '', DOCUMENT_AI_LOCATION: '',
        DOCUMENT_AI_OCR_PROCESSOR_ID: '', DOCUMENT_AI_OCR_PROCESSOR_VERSION: '',
        NEXT_FONT_GOOGLE_MOCKED_RESPONSES: fontMock,
      }
      console.log(run(node, [join(root, 'node_modules/next/dist/bin/next'), 'build', '--webpack'], { cwd: workspace, env: buildEnv }))
      console.log('Production build succeeded.')
    } finally {
      rmSync(workspace, { recursive: true, force: true })
    }
  }
} finally {
  let cleaned = !owned
  if (owned) {
    const stopped = spawnSync(node, [cli, 'stop', '--no-backup', '--workdir', workdir], { encoding: 'utf8' })
    if (stopped.status !== 0) console.error(`Cleanup failed: inspect exclusively owned ${project}; retained recovery config ${workdir}.`)
    else { cleaned = true; console.log('Removed exclusively owned matter-supporting-files stack and data.') }
  }
  if (cleaned) rmSync(workdir, { recursive: true, force: true })
}
