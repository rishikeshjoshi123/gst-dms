import { spawnSync } from 'node:child_process'
import { cpSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve, sep } from 'node:path'
import { acceptanceProjectPath, nodeModuleLaunch, requireNode24 } from './runtime.mjs'

const nodeExec = requireNode24()
const projectRoot = resolve(acceptanceProjectPath('.'))
const supabaseCli = acceptanceProjectPath('node_modules/supabase/dist/supabase.js')
const playwrightCli = acceptanceProjectPath('node_modules/@playwright/test/cli.js')
const docker = '/usr/local/bin/docker'
const profile = JSON.parse(readFileSync(
  acceptanceProjectPath('scripts/acceptance/onboarding-confirmation-profile.json'),
  'utf8',
))
const disposableRoot = mkdtempSync(join(realpathSync(tmpdir()), 'casechain-onboarding-confirmation-'))
const disposableSupabase = join(disposableRoot, 'supabase')
let stackStarted = false

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: projectRoot,
    stdio: 'inherit',
    ...options,
  })
  if (result.error) throw result.error
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? 'no status'}.`)
  return result
}

function statusEnvironment() {
  const status = spawnSync(nodeExec, [supabaseCli, 'status', '-o', 'env'], {
    cwd: disposableRoot,
    encoding: 'utf8',
  })
  if (status.status !== 0) throw new Error(status.stderr || 'Disposable Supabase status failed.')
  return Object.fromEntries(status.stdout.trim().split('\n').map((line) => {
    const separator = line.indexOf('=')
    return [line.slice(0, separator), line.slice(separator + 1).replace(/^"|"$/g, '')]
  }))
}

function assertLoopback(local) {
  for (const key of ['API_URL', 'DB_URL', 'INBUCKET_URL']) {
    if (!local[key]) throw new Error(`Disposable Supabase did not report ${key}.`)
    const url = new URL(local[key])
    if (!['127.0.0.1', 'localhost'].includes(url.hostname)) {
      throw new Error(`Refusing non-loopback ${key}.`)
    }
  }
  if (new URL(local.DB_URL).port !== profile.portMap['54322']) {
    throw new Error('Refusing a disposable database outside the confirmation profile port.')
  }
}

function resolveDatabaseContainer() {
  const result = spawnSync(docker, ['ps', '--format', '{{.Names}}|{{.Ports}}'], { encoding: 'utf8' })
  if (result.status !== 0) throw new Error(result.stderr || 'Unable to inspect local Docker containers.')
  const port = profile.portMap['54322']
  const matches = result.stdout.trim().split('\n').filter((line) =>
    line.startsWith('supabase_db_') && line.includes(`:${port}->5432/tcp`),
  )
  if (matches.length !== 1) throw new Error('Disposable onboarding database container was not resolved uniquely.')
  const container = matches[0].split('|')[0]
  if (container !== `supabase_db_${profile.projectId}`) {
    throw new Error('Resolved database container does not match the isolated profile.')
  }
  return container
}

function runSql(container, relativePath) {
  const input = readFileSync(acceptanceProjectPath(relativePath))
  run(docker, ['exec', '-i', container, 'psql', '-X', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], {
    input,
    stdio: ['pipe', 'inherit', 'inherit'],
  })
}

try {
  cpSync(acceptanceProjectPath('supabase'), disposableSupabase, { recursive: true })
  const sourceConfig = readFileSync(join(disposableSupabase, 'config.toml'), 'utf8')
  let confirmationConfig = sourceConfig.replace(
    /^project_id = "[^"]+"/m,
    `project_id = "${profile.projectId}"`,
  )
  for (const [from, to] of Object.entries(profile.portMap)) {
    confirmationConfig = confirmationConfig.replaceAll(from, to)
  }
  confirmationConfig = confirmationConfig
    .replace('site_url = "http://127.0.0.1:3000"', `site_url = "${profile.appUrl}"`)
    .replace(
      /^additional_redirect_urls = .*$/m,
      `additional_redirect_urls = ["${profile.appUrl}/auth/callback", "${profile.appUrl}/auth/callback?next=/onboarding"]`,
    )
    .replace('enable_confirmations = false', 'enable_confirmations = true')
  if (!confirmationConfig.includes('enable_confirmations = true')) {
    throw new Error('Confirmation-required profile was not materialized.')
  }
  writeFileSync(join(disposableSupabase, 'config.toml'), confirmationConfig)

  process.stdout.write(`Starting isolated confirmation-required Supabase profile ${profile.projectId}...\n`)
  stackStarted = true
  run(nodeExec, [
    supabaseCli,
    'start',
    '--exclude',
    'realtime,storage-api,imgproxy,postgres-meta,studio,edge-runtime,logflare,vector,supavisor',
  ], { cwd: disposableRoot })
  const local = statusEnvironment()
  assertLoopback(local)
  const container = resolveDatabaseContainer()
  runSql(container, 'scripts/acceptance/seed-onboarding-confirmation.sql')

  const playwright = nodeModuleLaunch(playwrightCli, [
    'test',
    '--config',
    'playwright.onboarding.config.ts',
    'tests/acceptance/onboarding.spec.ts',
  ])
  run(playwright.command, playwright.args, {
    env: {
      ...process.env,
      ACCEPTANCE_NODE_EXEC: nodeExec,
      ONBOARDING_SUPABASE_WORKDIR: disposableRoot,
      ONBOARDING_APP_URL: profile.appUrl,
      ONBOARDING_INBUCKET_URL: local.INBUCKET_URL,
    },
  })
  runSql(container, 'scripts/acceptance/verify-onboarding-confirmation.sql')
  process.stdout.write('Confirmation-required signup, captured mail, create, and join acceptance passed.\n')
} finally {
  if (stackStarted) {
    const stopped = spawnSync(nodeExec, [supabaseCli, 'stop', '--no-backup'], {
      cwd: disposableRoot,
      stdio: 'inherit',
    })
    if (stopped.status !== 0) process.stderr.write('Warning: isolated onboarding stack did not stop cleanly.\n')
  }
  const resolvedRoot = realpathSync(disposableRoot)
  const resolvedTemp = realpathSync(tmpdir())
  if (!resolvedRoot.startsWith(`${resolvedTemp}${sep}`)) {
    throw new Error('Refusing to remove a non-temporary acceptance directory.')
  }
  rmSync(resolvedRoot, { recursive: true, force: true })
}
