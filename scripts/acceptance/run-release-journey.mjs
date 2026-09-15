import { cpSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve, sep } from 'node:path'
import { randomBytes } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node = requireNode24()
const repository = process.cwd()
const profile = JSON.parse(readFileSync(join(repository, 'scripts/acceptance/release-journey-profile.json'), 'utf8'))
const root = mkdtempSync(join(realpathSync(tmpdir()), 'casechain-release-journey-'))
const supabaseRoot = join(root, 'supabase')
const cli = join(repository, 'node_modules/supabase/dist/supabase.js')
const container = `supabase_db_${profile.projectId}`
const ownerEmail = `release-owner-${randomBytes(6).toString('hex')}@acceptance.test`
let owned = false
let cleanupStarted = false
let activeChild = null

function run(command, args, options = {}) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, {
      cwd: options.cwd ?? repository,
      env: options.env ?? process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    activeChild = child
    let stdout = '', stderr = ''
    const limit = 30 * 1024 * 1024
    child.stdout.on('data', (chunk) => { stdout += chunk; if (stdout.length > limit) child.kill('SIGTERM') })
    child.stderr.on('data', (chunk) => { stderr += chunk; if (stderr.length > limit) child.kill('SIGTERM') })
    child.once('error', rejectRun)
    child.once('close', (status) => {
      if (activeChild === child) activeChild = null
      if (status !== 0) rejectRun(new Error(`${command} failed: ${stderr}\n${stdout}`))
      else resolveRun(stdout)
    })
  })
}

function assertLoopback(local) {
  for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL', 'STORAGE_S3_URL']) {
    if (!local[key]) throw new Error(`Disposable Supabase did not report ${key}.`)
    if (!['127.0.0.1', 'localhost'].includes(new URL(local[key]).hostname)) {
      throw new Error(`Refusing non-loopback ${key}.`)
    }
  }
  if (new URL(local.DB_URL).port !== profile.portMap['54322']) {
    throw new Error('Refusing a database outside the release-journey profile port.')
  }
}

async function verifyGeneratedTypes() {
  const typeRoot = mkdtempSync(join(root, 'types-'))
  try {
    cpSync(join(repository, 'scripts/generate-supabase-types.mjs'), join(typeRoot, 'scripts/generate-supabase-types.mjs'), { recursive: true })
    cpSync(join(repository, 'scripts/refine-supabase-types.mjs'), join(typeRoot, 'scripts/refine-supabase-types.mjs'), { recursive: true })
    cpSync(join(repository, 'src/lib/supabase/database.types.ts'), join(typeRoot, 'src/lib/supabase/database.types.ts'), { recursive: true })
    symlinkSync(resolve(repository, 'node_modules'), join(typeRoot, 'node_modules'), 'dir')
    const env = { ...process.env, PATH: `${join(repository, 'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}` }
    const args = ['scripts/generate-supabase-types.mjs', '--local', '--workdir', root]
    await run(node, args, { cwd: typeRoot, env })
    const first = readFileSync(join(typeRoot, 'src/lib/supabase/database.types.ts'), 'utf8')
    if (first !== readFileSync(join(repository, 'src/lib/supabase/database.types.ts'), 'utf8')) {
      throw new Error('Generated/refined database types differ from the checked-in types.')
    }
    await run(node, args, { cwd: typeRoot, env })
    if (readFileSync(join(typeRoot, 'src/lib/supabase/database.types.ts'), 'utf8') !== first) {
      throw new Error('Repeated generated/refined database types are not byte-stable.')
    }
    process.stdout.write('Generated/refined database types match the repository and repeat byte-identically.\n')
  } finally {
    rmSync(typeRoot, { recursive: true, force: true })
  }
}

async function waitForLocalService(url, label, { statusIsReady = (status) => status >= 200 && status < 500 } = {}) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(1_000) })
      if (statusIsReady(response.status)) return
    } catch {}
    await new Promise((resolveWait) => setTimeout(resolveWait, 250))
  }
  throw new Error(`${label} did not become ready on its expected loopback endpoint.`)
}

function cleanup() {
  if (cleanupStarted) return
  cleanupStarted = true
  activeChild?.kill('SIGTERM')
  let clean = !owned
  if (owned) {
    const stopped = spawnSync(node, [cli, 'stop', '--no-backup', '--workdir', root], { encoding: 'utf8' })
    if (stopped.status !== 0) process.stderr.write(`Cleanup failed; inspect exclusively owned ${profile.projectId} at ${root}.\n`)
    else {
      clean = true
      process.stdout.write(`Removed exclusively owned ${profile.projectId} stack and data.\n`)
    }
  }
  if (!clean) return
  const resolvedRoot = realpathSync(root)
  const resolvedTemp = realpathSync(tmpdir())
  if (!resolvedRoot.startsWith(`${resolvedTemp}${sep}`)) throw new Error('Refusing to remove a non-temporary acceptance directory.')
  rmSync(resolvedRoot, { recursive: true, force: true })
  rmSync('/tmp/casechain-release-journey-playwright', { recursive: true, force: true })
}

for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143]]) {
  process.once(signal, () => {
    cleanup()
    process.exit(code)
  })
}

try {
  const existing = await run('docker', ['ps', '-a', '--format', '{{.Names}}'])
  if (existing.split('\n').includes(container)) {
    throw new Error(`The isolated ${profile.projectId} project is already owned by another run; nothing was changed.`)
  }
  cpSync(join(repository, 'supabase'), supabaseRoot, { recursive: true })
  let config = readFileSync(join(supabaseRoot, 'config.toml'), 'utf8')
    .replace(/^project_id = "[^"]+"/m, `project_id = "${profile.projectId}"`)
  for (const [from, to] of Object.entries(profile.portMap)) config = config.replaceAll(from, to)
  config = config
    .replace('site_url = "http://127.0.0.1:3000"', `site_url = "${profile.appUrl}"`)
    .replace(/^additional_redirect_urls = .*$/m, `additional_redirect_urls = ["${profile.appUrl}/auth/callback", "${profile.appUrl}/auth/callback?next=/onboarding"]`)
    .replace('enable_confirmations = false', 'enable_confirmations = true')
    .replace(/(\[db\.seed\][\s\S]*?enabled = )true/, '$1false')
  if (!config.includes('enable_confirmations = true')) throw new Error('Confirmation-required auth was not configured.')
  writeFileSync(join(supabaseRoot, 'config.toml'), config)

  process.stdout.write(`Replaying all migrations in isolated ${profile.projectId} on DB ${profile.portMap['54322']} (${root}).\n`)
  owned = true
  await run(node, [cli, 'start', '--workdir', root, '--exclude', 'realtime,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor'])
  const local = JSON.parse(await run(node, [cli, 'status', '--workdir', root, '-o', 'json']))
  assertLoopback(local)
  await Promise.all([
    waitForLocalService(`${local.API_URL}/auth/v1/health`, 'Local Auth'),
    waitForLocalService(`${local.INBUCKET_URL}/api/v1/mailbox/release-readiness@acceptance.test`, 'Captured mail'),
  ])
  process.stdout.write('Local Auth and captured mail are ready for confirmation-required signup.\n')
  const resolved = (await run('docker', ['ps', '--format', '{{.Names}}|{{.Ports}}']))
    .split('\n').filter((line) => line.startsWith(`${container}|`) && line.includes(`:${profile.portMap['54322']}->5432/tcp`))
  if (resolved.length !== 1) throw new Error('The release-journey database container was not resolved uniquely.')

  const lint = await run(node, [cli, 'db', 'lint', '--local', '--workdir', root, '--level', 'error'])
  process.stdout.write(lint)
  if (JSON.parse(lint).results?.length) throw new Error('Disposable database lint returned errors.')
  await verifyGeneratedTypes()

  process.stdout.write('Running one stateful production-webpack Chromium release journey.\n')
  process.stdout.write(await run(node, ['node_modules/@playwright/test/cli.js', 'test', '--config', 'playwright.release-journey.config.ts'], {
    env: {
      ...process.env,
      RELEASE_JOURNEY_SUPABASE_WORKDIR: root,
      RELEASE_JOURNEY_INBUCKET_URL: local.INBUCKET_URL,
      RELEASE_JOURNEY_OWNER_EMAIL: ownerEmail,
    },
  }))
} finally {
  cleanup()
}
